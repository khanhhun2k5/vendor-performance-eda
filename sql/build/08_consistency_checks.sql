-- =====================================================================
-- 08_consistency_checks.sql — Kiểm tra NGÀY THÁNG và NHẤT QUÁN GIỮA CÁC FILE CSV.
-- Tạo:
--   dq_dates        : hồ sơ từng cột ngày (định dạng, min/max, ngoài năm 2024)
--   dq_calendar     : 366 ngày của 2024 — ngày nào thiếu dữ liệu bán / nhận hàng
--   mart_stock_flow : cân đối tồn kho từng InventoryId: đầu kỳ + mua − bán = cuối kỳ ?
--   dq_consistency  : danh sách kiểm tra nhất quán (nhóm, số dòng vi phạm, mức độ, ghi chú)
-- Mỗi bảng lớn chỉ quét 1 lần nhờ bảng TEMP tổng hợp thuộc tính theo Brand.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. Hồ sơ cột ngày
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dq_dates;
CREATE TABLE dq_dates AS
WITH cols(table_name, column_name, v) AS (
    SELECT 'sales', 'SalesDate', SalesDate FROM raw.sales
    UNION ALL SELECT 'purchases', 'PODate', PODate FROM raw.purchases
    UNION ALL SELECT 'purchases', 'ReceivingDate', ReceivingDate FROM raw.purchases
    UNION ALL SELECT 'purchases', 'InvoiceDate', InvoiceDate FROM raw.purchases
    UNION ALL SELECT 'purchases', 'PayDate', PayDate FROM raw.purchases
    UNION ALL SELECT 'vendor_invoice', 'PODate', PODate FROM raw.vendor_invoice
    UNION ALL SELECT 'vendor_invoice', 'InvoiceDate', InvoiceDate FROM raw.vendor_invoice
    UNION ALL SELECT 'vendor_invoice', 'PayDate', PayDate FROM raw.vendor_invoice
    UNION ALL SELECT 'begin_inventory', 'startDate', startDate FROM raw.begin_inventory
    UNION ALL SELECT 'end_inventory', 'endDate', endDate FROM raw.end_inventory
)
SELECT table_name, column_name,
       COUNT(*)                                              AS n_rows,
       SUM(v IS NULL)                                        AS n_null,
       SUM(v IS NOT NULL AND (date(v) IS NULL OR date(v) <> v)) AS n_bad_format,   -- không phải YYYY-MM-DD hợp lệ
       MIN(v)                                                AS min_date,
       MAX(v)                                                AS max_date,
       COUNT(DISTINCT v)                                     AS n_distinct_days,
       SUM(v < '2024-01-01')                                 AS n_before_2024,
       SUM(v > '2024-12-31')                                 AS n_after_2024
FROM cols
GROUP BY table_name, column_name;

-- ---------------------------------------------------------------------
-- B. Lịch 2024 (năm nhuận, 366 ngày) — dựa trên mart đã có, không quét lại
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dq_calendar;
CREATE TABLE dq_calendar AS
WITH RECURSIVE d(day) AS (
    SELECT '2024-01-01'
    UNION ALL SELECT date(day, '+1 day') FROM d WHERE day < '2024-12-31'
)
SELECT d.day,
       CAST(strftime('%w', d.day) AS INTEGER)                     AS weekday,    -- 0 = Chủ nhật
       s.dollars IS NOT NULL                                      AS has_sales,
       p.dollars IS NOT NULL                                      AS has_receiving,
       COALESCE(s.dollars, 0)                                     AS sales_dollars,
       COALESCE(p.dollars, 0)                                     AS receiving_dollars
FROM d
LEFT JOIN (SELECT SalesDate AS day, SUM(dollars) AS dollars FROM mart_sales_daily GROUP BY 1) s USING (day)
LEFT JOIN (SELECT ReceivingDate AS day, SUM(dollars) AS dollars FROM mart_purchases_daily GROUP BY 1) p USING (day);

-- ---------------------------------------------------------------------
-- C. Cân đối tồn kho theo InventoryId
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS temp.flow_s;
CREATE TEMP TABLE flow_s AS
SELECT InventoryId, MIN(Store) AS Store, MIN(Brand) AS Brand, SUM(SalesQuantity) AS sold
FROM raw.sales GROUP BY InventoryId;
CREATE UNIQUE INDEX temp.ux_flow_s ON flow_s(InventoryId);

DROP TABLE IF EXISTS temp.flow_p;
CREATE TEMP TABLE flow_p AS
SELECT InventoryId, MIN(Store) AS Store, MIN(Brand) AS Brand, SUM(Quantity) AS purchased
FROM raw.purchases GROUP BY InventoryId;
CREATE UNIQUE INDEX temp.ux_flow_p ON flow_p(InventoryId);

DROP TABLE IF EXISTS mart_stock_flow;
CREATE TABLE mart_stock_flow AS
WITH k AS (
    SELECT InventoryId FROM mart_inventory
    UNION SELECT InventoryId FROM flow_s
    UNION SELECT InventoryId FROM flow_p
)
SELECT k.InventoryId,
       COALESCE(i.Store, s.Store, p.Store)                       AS Store,
       COALESCE(i.Brand, s.Brand, p.Brand)                       AS Brand,
       COALESCE(i.begin_onhand, 0)                               AS begin_onhand,
       COALESCE(p.purchased, 0)                                  AS purchased,
       COALESCE(s.sold, 0)                                       AS sold,
       COALESCE(i.end_onhand, 0)                                 AS end_onhand,
       COALESCE(i.begin_onhand, 0) + COALESCE(p.purchased, 0)
         - COALESCE(s.sold, 0) - COALESCE(i.end_onhand, 0)       AS gap,          -- ≠ 0 ⇒ hao hụt / sai số liệu
       i.InventoryId IS NULL                                     AS not_in_snapshots
FROM k
LEFT JOIN mart_inventory i USING (InventoryId)
LEFT JOIN flow_s s USING (InventoryId)
LEFT JOIN flow_p p USING (InventoryId);

CREATE INDEX ix_stock_flow_store ON mart_stock_flow(Store);

-- ---------------------------------------------------------------------
-- D. Thuộc tính theo Brand của từng file (1 lần quét / bảng lớn)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS temp.attr_sales;
CREATE TEMP TABLE attr_sales AS
SELECT s.Brand,
       COUNT(*)                                                  AS n_rows,
       COUNT(DISTINCT s.Description)                             AS n_desc,
       COUNT(DISTINCT s.Size)                                    AS n_size,
       COUNT(DISTINCT s.Classification)                          AS n_class,
       COUNT(DISTINCT s.VendorNo)                                AS n_vendor,
       MIN(s.Description)                                        AS Description,
       MIN(s.Size)                                               AS Size,
       MIN(s.Classification)                                     AS Classification,
       MIN(s.VendorNo)                                           AS VendorNumber,
       MIN(s.Volume)                                             AS Volume,
       SUM(ABS(s.SalesPrice - p.Price) > 0.005)                  AS n_price_diff,
       SUM(ABS(s.SalesDollars - s.SalesPrice * s.SalesQuantity) > 0.01) AS n_bad_amount,
       SUM(s.SalesQuantity <= 0)                                 AS n_nonpos_qty,
       SUM(s.InventoryId NOT LIKE s.Store || '\_%\_' || s.Brand ESCAPE '\') AS n_bad_invid,
       SUM(CASE s.Classification
             WHEN 1 THEN s.ExciseTax / (s.SalesQuantity * s.Volume / 1000.0) NOT BETWEEN 0.9 AND 1.2
             ELSE        s.ExciseTax / (s.SalesQuantity * s.Volume / 1000.0) NOT BETWEEN 0.1 AND 0.25 END) AS n_odd_excise
FROM raw.sales s
LEFT JOIN raw.purchase_prices p ON p.Brand = s.Brand
GROUP BY s.Brand;

DROP TABLE IF EXISTS temp.attr_purch;
CREATE TEMP TABLE attr_purch AS
SELECT u.Brand,
       COUNT(*)                                                  AS n_rows,
       COUNT(DISTINCT u.Description)                             AS n_desc,
       COUNT(DISTINCT u.Classification)                          AS n_class,
       COUNT(DISTINCT u.VendorNumber)                            AS n_vendor,
       MIN(u.Description)                                        AS Description,
       MIN(u.Size)                                               AS Size,
       MIN(u.Classification)                                     AS Classification,
       MIN(u.VendorNumber)                                       AS VendorNumber,
       SUM(ABS(u.PurchasePrice - p.PurchasePrice) > 0.005)       AS n_cost_diff,
       SUM(ABS(u.Dollars - u.PurchasePrice * u.Quantity) > 0.01) AS n_bad_amount,
       SUM(u.Quantity <= 0)                                      AS n_nonpos_qty,
       SUM(u.InventoryId NOT LIKE u.Store || '\_%\_' || u.Brand ESCAPE '\') AS n_bad_invid,
       SUM(u.ReceivingDate < u.PODate)                           AS n_recv_before_po,
       SUM(u.InvoiceDate < u.PODate)                             AS n_inv_before_po,
       SUM(u.PayDate < u.InvoiceDate)                            AS n_pay_before_inv
FROM raw.purchases u
LEFT JOIN raw.purchase_prices p ON p.Brand = u.Brand
GROUP BY u.Brand;

-- Chuẩn hóa chuỗi Size → mL/chai để phân biệt "khác cách viết" với "khác thật"
DROP TABLE IF EXISTS temp.size_norm;
CREATE TEMP TABLE size_norm AS
WITH sizes(Size) AS (
    SELECT Size FROM raw.purchase_prices UNION SELECT Size FROM attr_purch UNION SELECT Size FROM attr_sales
    UNION SELECT Size FROM raw.begin_inventory UNION SELECT Size FROM raw.end_inventory
)
SELECT Size,
       CASE
           WHEN Size IS NULL OR Size = 'Unknown'      THEN NULL
           WHEN Size LIKE 'Liter%'                    THEN 1000.0
           WHEN Size LIKE '%mL%' OR Size LIKE '%ml%'  THEN CAST(Size AS REAL)
           WHEN Size LIKE '%L%'                       THEN CAST(Size AS REAL) * 1000
           ELSE CAST(Size AS REAL)
       END AS ml
FROM sizes;

-- ---------------------------------------------------------------------
-- E. Bảng kết quả kiểm tra nhất quán
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dq_consistency;
CREATE TABLE dq_consistency (
    check_group TEXT,     -- Ngày tháng | Khóa & liên kết | Tồn kho | Thuộc tính sản phẩm | Giá | Số học | Hóa đơn
    check_name  TEXT,
    tables      TEXT,
    n_affected  REAL,
    n_total     REAL,
    severity    TEXT,     -- Lỗi | Cảnh báo | Đạt
    note        TEXT
);

-- ----- Ngày tháng -----
INSERT INTO dq_consistency
SELECT 'Ngày tháng', 'Ngày sai định dạng YYYY-MM-DD / không tồn tại', 'mọi cột *Date',
       SUM(n_bad_format), SUM(n_rows), CASE WHEN SUM(n_bad_format) = 0 THEN 'Đạt' ELSE 'Lỗi' END,
       'Kiểm bằng date(v) = v (bắt cả 2024-02-30)'
FROM dq_dates;

INSERT INTO dq_consistency
SELECT 'Ngày tháng', 'Ngày giao dịch (SalesDate/ReceivingDate) ngoài năm 2024', 'sales, purchases',
       SUM(n_before_2024 + n_after_2024), SUM(n_rows),
       CASE WHEN SUM(n_before_2024 + n_after_2024) = 0 THEN 'Đạt' ELSE 'Lỗi' END, 'Phạm vi kỳ phân tích'
FROM dq_dates WHERE column_name IN ('SalesDate', 'ReceivingDate');

INSERT INTO dq_consistency
SELECT 'Ngày tháng', 'Ngày chứng từ ngoài 2024 (PODate 2023, Invoice/PayDate 2025)', 'purchases, vendor_invoice',
       SUM(n_before_2024 + n_after_2024), SUM(n_rows), 'Cảnh báo', 'Hợp lệ: đơn vắt qua đầu/cuối kỳ'
FROM dq_dates WHERE column_name IN ('PODate', 'InvoiceDate', 'PayDate');

INSERT INTO dq_consistency
SELECT 'Ngày tháng', 'startDate/endDate không phải hằng số 2024-01-01 / 2024-12-31', 'begin/end_inventory',
       SUM(n_distinct_days <> 1 OR (column_name = 'startDate' AND min_date <> '2024-01-01')
                                OR (column_name = 'endDate' AND min_date <> '2024-12-31')), 2,
       CASE WHEN SUM(n_distinct_days <> 1) = 0 THEN 'Đạt' ELSE 'Lỗi' END, 'Ảnh chụp tồn kho'
FROM dq_dates WHERE column_name IN ('startDate', 'endDate');

INSERT INTO dq_consistency
SELECT 'Ngày tháng', 'Ngày trong năm KHÔNG có dữ liệu bán: ' || COALESCE(GROUP_CONCAT(day, ', '), '—'),
       'sales', COUNT(*), 366, CASE WHEN COUNT(*) = 0 THEN 'Đạt' ELSE 'Cảnh báo' END,
       'Năm nhuận 366 ngày; ngày thiếu làm giảm doanh thu tháng tương ứng'
FROM dq_calendar WHERE NOT has_sales;

INSERT INTO dq_consistency
SELECT 'Ngày tháng', 'Ngày trong năm KHÔNG có nhận hàng: ' || COALESCE(GROUP_CONCAT(day, ', '), '—'),
       'purchases', COUNT(*), 366, CASE WHEN COUNT(*) = 0 THEN 'Đạt' ELSE 'Cảnh báo' END,
       'Nhận hàng diễn ra cả cuối tuần'
FROM dq_calendar WHERE NOT has_receiving;

INSERT INTO dq_consistency
SELECT 'Ngày tháng', 'Thứ tự ngày sai trong purchases (nhận < đặt, hóa đơn < đặt, trả < hóa đơn)', 'purchases',
       SUM(n_recv_before_po + n_inv_before_po + n_pay_before_inv), SUM(n_rows),
       CASE WHEN SUM(n_recv_before_po + n_inv_before_po + n_pay_before_inv) = 0 THEN 'Đạt' ELSE 'Lỗi' END, ''
FROM attr_purch;

INSERT INTO dq_consistency
SELECT 'Ngày tháng', 'Thứ tự ngày sai trong vendor_invoice (hóa đơn < đặt, trả < hóa đơn)', 'vendor_invoice',
       SUM(InvoiceDate < PODate OR PayDate < InvoiceDate), COUNT(*),
       CASE WHEN SUM(InvoiceDate < PODate OR PayDate < InvoiceDate) = 0 THEN 'Đạt' ELSE 'Lỗi' END, ''
FROM raw.vendor_invoice;

INSERT INTO dq_consistency
SELECT 'Ngày tháng', 'Hóa đơn xuất trước khi nhận đủ hàng (InvoiceDate < ngày nhận cuối)', 'mart_po',
       SUM(invoice_lag_days < 0), COUNT(*), CASE WHEN SUM(invoice_lag_days < 0) = 0 THEN 'Đạt' ELSE 'Cảnh báo' END,
       'Có thể là hóa đơn theo đợt giao đầu'
FROM mart_po;

-- ----- Khóa & liên kết -----
INSERT INTO dq_consistency
SELECT 'Khóa & liên kết', 'Khóa chính bị trùng (InventoryId tồn kho, Brand danh mục, PONumber hóa đơn)',
       'begin/end_inventory, purchase_prices, vendor_invoice',
       (SELECT COUNT(*) - COUNT(DISTINCT InventoryId) FROM raw.begin_inventory)
     + (SELECT COUNT(*) - COUNT(DISTINCT InventoryId) FROM raw.end_inventory)
     + (SELECT COUNT(*) - COUNT(DISTINCT Brand) FROM raw.purchase_prices)
     + (SELECT COUNT(*) - COUNT(DISTINCT PONumber) FROM raw.vendor_invoice),
       (SELECT COUNT(*) FROM raw.begin_inventory) + (SELECT COUNT(*) FROM raw.end_inventory)
     + (SELECT COUNT(*) FROM raw.purchase_prices) + (SELECT COUNT(*) FROM raw.vendor_invoice),
       'Đạt', '';
UPDATE dq_consistency SET severity = 'Lỗi' WHERE check_name LIKE 'Khóa chính bị trùng%' AND n_affected > 0;

INSERT INTO dq_consistency
SELECT 'Khóa & liên kết', 'Brand trong giao dịch/tồn kho không có trong danh mục purchase_prices',
       'sales, purchases, begin/end_inventory',
       (SELECT COUNT(*) FROM attr_sales WHERE Brand NOT IN (SELECT Brand FROM raw.purchase_prices))
     + (SELECT COUNT(*) FROM attr_purch WHERE Brand NOT IN (SELECT Brand FROM raw.purchase_prices))
     + (SELECT COUNT(DISTINCT Brand) FROM mart_inventory WHERE Brand NOT IN (SELECT Brand FROM raw.purchase_prices)),
       (SELECT COUNT(*) FROM attr_sales) + (SELECT COUNT(*) FROM attr_purch)
     + (SELECT COUNT(DISTINCT Brand) FROM mart_inventory),
       'Đạt', 'Số Brand';
UPDATE dq_consistency SET severity = 'Lỗi' WHERE check_name LIKE 'Brand trong giao dịch%' AND n_affected > 0;

INSERT INTO dq_consistency
SELECT 'Khóa & liên kết', 'InventoryId không theo mẫu Store_City_Brand khớp cột Store/Brand', 'sales, purchases',
       (SELECT SUM(n_bad_invid) FROM attr_sales) + (SELECT SUM(n_bad_invid) FROM attr_purch),
       (SELECT SUM(n_rows) FROM attr_sales) + (SELECT SUM(n_rows) FROM attr_purch),
       'Đạt', 'Số dòng';
UPDATE dq_consistency SET severity = 'Lỗi' WHERE check_name LIKE 'InventoryId không theo mẫu%' AND n_affected > 0;

INSERT INTO dq_consistency
SELECT 'Khóa & liên kết', 'Store gắn với > 1 City', 'begin/end_inventory',
       COUNT(*), (SELECT COUNT(*) FROM dim_store), CASE WHEN COUNT(*) = 0 THEN 'Đạt' ELSE 'Lỗi' END, ''
FROM (SELECT Store FROM (SELECT Store, City FROM raw.begin_inventory UNION
                         SELECT Store, City FROM raw.end_inventory WHERE City IS NOT NULL)
      GROUP BY Store HAVING COUNT(DISTINCT City) > 1);

INSERT INTO dq_consistency
SELECT 'Khóa & liên kết', 'InventoryId có giao dịch nhưng không có trong ảnh chụp tồn kho đầu/cuối kỳ',
       'sales, purchases vs inventory', SUM(not_in_snapshots), COUNT(*), 'Cảnh báo',
       'Mua vào và bán hết trong năm (tồn = 0 ở cả 2 mốc) — cân đối vẫn khớp'
FROM mart_stock_flow;

-- ----- Tồn kho -----
INSERT INTO dq_consistency
SELECT 'Tồn kho', 'Cân đối lệch: đầu kỳ + mua − bán ≠ cuối kỳ', 'begin/end_inventory, purchases, sales',
       SUM(gap <> 0), COUNT(*), CASE WHEN SUM(gap <> 0) = 0 THEN 'Đạt' ELSE 'Lỗi' END,
       'Tổng lệch (chai) = ' || SUM(gap)
FROM mart_stock_flow;

INSERT INTO dq_consistency
SELECT 'Tồn kho', 'Bán vượt lượng sẵn có (đầu kỳ + mua < bán)', 'mart_stock_flow',
       SUM(begin_onhand + purchased < sold), COUNT(*),
       CASE WHEN SUM(begin_onhand + purchased < sold) = 0 THEN 'Đạt' ELSE 'Lỗi' END, ''
FROM mart_stock_flow;

INSERT INTO dq_consistency
SELECT 'Tồn kho', 'onHand âm', 'begin/end_inventory',
       SUM(begin_onhand < 0) + SUM(end_onhand < 0), 2 * COUNT(*),
       CASE WHEN SUM(begin_onhand < 0) + SUM(end_onhand < 0) = 0 THEN 'Đạt' ELSE 'Lỗi' END, ''
FROM mart_inventory;

-- ----- Thuộc tính sản phẩm (so với danh mục purchase_prices) -----
INSERT INTO dq_consistency
SELECT 'Thuộc tính sản phẩm', 'Size viết khác danh mục nhưng CÙNG dung tích (vd 1.5L vs 1500mL)', 'purchases vs purchase_prices',
       SUM(a.Size <> p.Size AND na.ml = np.ml), COUNT(*), 'Cảnh báo', 'Chỉ khác cách viết — dùng Volume khi cần số'
FROM attr_purch a JOIN raw.purchase_prices p USING (Brand)
LEFT JOIN size_norm na ON na.Size = a.Size LEFT JOIN size_norm np ON np.Size = p.Size;

INSERT INTO dq_consistency
SELECT 'Thuộc tính sản phẩm', 'Size KHÁC dung tích danh mục (vd 250mL 4 Pk vs 1000mL)', 'purchases vs purchase_prices',
       SUM(na.ml <> np.ml), COUNT(*), CASE WHEN SUM(na.ml <> np.ml) = 0 THEN 'Đạt' ELSE 'Cảnh báo' END,
       'Đa phần là gói nhiều chai: danh mục ghi tổng, giao dịch ghi theo chai'
FROM attr_purch a JOIN raw.purchase_prices p USING (Brand)
LEFT JOIN size_norm na ON na.Size = a.Size LEFT JOIN size_norm np ON np.Size = p.Size;

INSERT INTO dq_consistency
SELECT 'Thuộc tính sản phẩm', 'Size viết khác danh mục', 'end_inventory vs purchase_prices',
       SUM(e.Size <> p.Size), COUNT(*), 'Cảnh báo', 'Số dòng tồn kho; chủ yếu L ↔ mL'
FROM raw.end_inventory e JOIN raw.purchase_prices p USING (Brand);

INSERT INTO dq_consistency
SELECT 'Thuộc tính sản phẩm', '1 Brand có > 1 Size trong sales', 'sales',
       SUM(n_size > 1), COUNT(*), CASE WHEN SUM(n_size > 1) = 0 THEN 'Đạt' ELSE 'Cảnh báo' END, ''
FROM attr_sales;

INSERT INTO dq_consistency
SELECT 'Thuộc tính sản phẩm', 'Description khác danh mục', 'begin_inventory vs purchase_prices',
       SUM(b.Description <> p.Description), COUNT(*), 'Cảnh báo', 'Vd "Glass Pack" ↔ "VAP"; dùng Brand làm khóa, không dùng tên'
FROM raw.begin_inventory b JOIN raw.purchase_prices p USING (Brand);

INSERT INTO dq_consistency
SELECT 'Thuộc tính sản phẩm', 'Description khác danh mục', 'sales / purchases vs purchase_prices',
       (SELECT SUM(a.Description <> p.Description) FROM attr_sales a JOIN raw.purchase_prices p USING (Brand))
     + (SELECT SUM(a.Description <> p.Description) FROM attr_purch a JOIN raw.purchase_prices p USING (Brand)),
       (SELECT COUNT(*) FROM attr_sales) + (SELECT COUNT(*) FROM attr_purch), 'Đạt', 'Số Brand';
UPDATE dq_consistency SET severity = 'Cảnh báo'
WHERE check_name = 'Description khác danh mục' AND tables LIKE 'sales%' AND n_affected > 0;

INSERT INTO dq_consistency
SELECT 'Thuộc tính sản phẩm', 'Classification khác danh mục', 'sales / purchases vs purchase_prices',
       (SELECT SUM(a.Classification <> p.Classification OR a.n_class > 1) FROM attr_sales a JOIN raw.purchase_prices p USING (Brand))
     + (SELECT SUM(a.Classification <> p.Classification OR a.n_class > 1) FROM attr_purch a JOIN raw.purchase_prices p USING (Brand)),
       (SELECT COUNT(*) FROM attr_sales) + (SELECT COUNT(*) FROM attr_purch), 'Đạt', 'Số Brand';
UPDATE dq_consistency SET severity = 'Lỗi' WHERE check_name = 'Classification khác danh mục' AND n_affected > 0;

INSERT INTO dq_consistency
SELECT 'Thuộc tính sản phẩm', 'Volume trong sales khác Volume danh mục', 'sales vs purchase_prices',
       SUM(p.Volume GLOB '[0-9]*' AND a.Volume <> CAST(p.Volume AS REAL)), COUNT(*), 'Đạt', 'Số Brand'
FROM attr_sales a JOIN raw.purchase_prices p USING (Brand);
UPDATE dq_consistency SET severity = 'Lỗi' WHERE check_name LIKE 'Volume trong sales%' AND n_affected > 0;

-- ----- Nhà cung cấp -----
INSERT INTO dq_consistency
SELECT 'Nhà cung cấp', 'Brand bán/mua dưới VendorNumber khác danh mục', 'sales / purchases vs purchase_prices',
       (SELECT SUM(a.VendorNumber <> p.VendorNumber OR a.n_vendor > 1) FROM attr_sales a JOIN raw.purchase_prices p USING (Brand))
     + (SELECT SUM(a.VendorNumber <> p.VendorNumber OR a.n_vendor > 1) FROM attr_purch a JOIN raw.purchase_prices p USING (Brand)),
       (SELECT COUNT(*) FROM attr_sales) + (SELECT COUNT(*) FROM attr_purch), 'Cảnh báo',
       'Số Brand; KPI NCC tính theo NCC thực giao dịch, không theo danh mục';

INSERT INTO dq_consistency
WITH names AS (
    SELECT VendorNumber AS v, TRIM(VendorName) AS n FROM raw.purchase_prices
    UNION SELECT DISTINCT VendorNumber, TRIM(VendorName) FROM raw.vendor_invoice
    UNION SELECT DISTINCT VendorNumber, TRIM(VendorName) FROM raw.purchases
)
SELECT 'Nhà cung cấp', '1 VendorNumber có > 1 tên: ' ||
       COALESCE((SELECT GROUP_CONCAT(v || ' = ' || ns, '; ') FROM
                 (SELECT v, GROUP_CONCAT(n, ' / ') AS ns FROM names GROUP BY v HAVING COUNT(*) > 1)), '—'),
       'purchase_prices, purchases, vendor_invoice',
       (SELECT COUNT(*) FROM (SELECT v FROM names GROUP BY v HAVING COUNT(*) > 1)),
       (SELECT COUNT(DISTINCT v) FROM names), 'Cảnh báo', 'Đổi tên/sáp nhập — gộp theo mã';

INSERT INTO dq_consistency
WITH names AS (
    SELECT VendorNumber AS v, TRIM(VendorName) AS n FROM raw.purchase_prices
    UNION SELECT DISTINCT VendorNumber, TRIM(VendorName) FROM raw.vendor_invoice
)
SELECT 'Nhà cung cấp', '1 tên NCC dùng > 1 VendorNumber', 'purchase_prices, vendor_invoice',
       (SELECT COUNT(*) FROM (SELECT n FROM names GROUP BY n HAVING COUNT(DISTINCT v) > 1)),
       (SELECT COUNT(DISTINCT n) FROM names), 'Đạt', '';
UPDATE dq_consistency SET severity = 'Lỗi' WHERE check_name = '1 tên NCC dùng > 1 VendorNumber' AND n_affected > 0;

-- ----- Giá -----
INSERT INTO dq_consistency
SELECT 'Giá', 'Giá mua (purchases) khác giá mua danh mục', 'purchases vs purchase_prices',
       SUM(n_cost_diff), SUM(n_rows), CASE WHEN SUM(n_cost_diff) = 0 THEN 'Đạt' ELSE 'Cảnh báo' END, 'Số dòng'
FROM attr_purch;

INSERT INTO dq_consistency
SELECT 'Giá', 'Giá bán (sales) khác giá niêm yết danh mục', 'sales vs purchase_prices',
       SUM(n_price_diff), SUM(n_rows), 'Cảnh báo',
       'Giá bán thay đổi theo thời gian/cửa hàng; danh mục là giá tham chiếu — tính doanh thu từ SalesDollars'
FROM attr_sales;

INSERT INTO dq_consistency
SELECT 'Giá', 'Giá tồn đầu kỳ khác giá niêm yết danh mục', 'begin_inventory vs purchase_prices',
       SUM(ABS(b.Price - p.Price) > 0.005), COUNT(*), 'Cảnh báo', 'Giá thời điểm 01/01'
FROM raw.begin_inventory b JOIN raw.purchase_prices p USING (Brand);

INSERT INTO dq_consistency
SELECT 'Giá', 'Giá tồn cuối kỳ khác giá niêm yết danh mục', 'end_inventory vs purchase_prices',
       SUM(ABS(e.Price - p.Price) > 0.005), COUNT(*), 'Cảnh báo', 'Giá thời điểm 31/12'
FROM raw.end_inventory e JOIN raw.purchase_prices p USING (Brand);

-- ----- Số học -----
INSERT INTO dq_consistency
SELECT 'Số học', 'Thành tiền ≠ đơn giá × số lượng', 'sales, purchases',
       (SELECT SUM(n_bad_amount) FROM attr_sales) + (SELECT SUM(n_bad_amount) FROM attr_purch),
       (SELECT SUM(n_rows) FROM attr_sales) + (SELECT SUM(n_rows) FROM attr_purch), 'Đạt', 'Ngưỡng $0,01';
UPDATE dq_consistency SET severity = 'Lỗi' WHERE check_name LIKE 'Thành tiền%' AND n_affected > 0;

INSERT INTO dq_consistency
SELECT 'Số học', 'Số lượng ≤ 0', 'sales, purchases',
       (SELECT SUM(n_nonpos_qty) FROM attr_sales) + (SELECT SUM(n_nonpos_qty) FROM attr_purch),
       (SELECT SUM(n_rows) FROM attr_sales) + (SELECT SUM(n_rows) FROM attr_purch), 'Đạt', '';
UPDATE dq_consistency SET severity = 'Lỗi' WHERE check_name = 'Số lượng ≤ 0' AND n_affected > 0;

INSERT INTO dq_consistency
SELECT 'Số học', 'Thuế tiêu thụ/lít ngoài khoảng của nhóm (rượu mạnh 0,9–1,2; vang 0,1–0,25 USD/L)', 'sales',
       SUM(n_odd_excise), SUM(n_rows), CASE WHEN SUM(n_odd_excise) = 0 THEN 'Đạt' ELSE 'Cảnh báo' END,
       'ExciseTax ≈ mức thuế/lít × dung tích × số lượng'
FROM attr_sales;

-- ----- Hóa đơn (kết quả ghép ở 03_purchase_marts.sql) -----
INSERT INTO dq_consistency
SELECT 'Hóa đơn', 'Số PO trên hóa đơn không khớp PO thật (đã ghép lại theo NCC+SL+tiền)', 'vendor_invoice vs purchases',
       SUM(match_type <> 'khớp số PO'), COUNT(*), 'Lỗi',
       'Từ PO 12311 (PODate ≥ 25/09/2024); PODate hóa đơn lệch ±' || CAST(MAX(ABS(podate_shift_days)) AS INTEGER) || ' ngày'
FROM map_invoice_po;

INSERT INTO dq_consistency
SELECT 'Hóa đơn', 'Ngày hóa đơn / ngày trả trên hóa đơn ≠ ngày ghi trên dòng mua', 'vendor_invoice vs purchases',
       SUM(invoice_date_mismatch OR pay_date_mismatch), COUNT(*), 'Cảnh báo', 'pay_days dùng ngày trên hóa đơn'
FROM mart_po;

INSERT INTO dq_consistency
SELECT 'Hóa đơn', 'Ngày/NCC thống nhất giữa các dòng của cùng 1 PO trong purchases', 'purchases',
       SUM(nd > 1 OR ni > 1 OR np > 1 OR nv > 1), COUNT(*),
       CASE WHEN SUM(nd > 1 OR ni > 1 OR np > 1 OR nv > 1) = 0 THEN 'Đạt' ELSE 'Lỗi' END, ''
FROM (SELECT PONumber, COUNT(DISTINCT PODate) nd, COUNT(DISTINCT InvoiceDate) ni,
             COUNT(DISTINCT PayDate) np, COUNT(DISTINCT VendorNumber) nv
      FROM raw.purchases GROUP BY PONumber);

INSERT INTO dq_consistency
SELECT 'Hóa đơn', 'PO giao nhiều đợt (≥ 2 ngày nhận) — không phải dòng trùng', 'purchases',
       SUM(FirstReceivingDate <> LastReceivingDate), COUNT(*), 'Cảnh báo',
       'Giải thích các cặp (PONumber, InventoryId) lặp lại'
FROM mart_po;

DROP TABLE IF EXISTS temp.flow_s;
DROP TABLE IF EXISTS temp.flow_p;
DROP TABLE IF EXISTS temp.attr_sales;
DROP TABLE IF EXISTS temp.attr_purch;
DROP TABLE IF EXISTS temp.size_norm;
