-- =====================================================================
-- 03_purchase_marts.sql — Tổng hợp purchases (2,37 triệu dòng) + ghép vendor_invoice.
-- Thời gian (ngày) tính bằng julianday(). Định nghĩa lead time (thống nhất toàn dự án):
--   lead_days            = ngày nhận CUỐI (nhận đủ hàng) − PODate   [cấp PO, chỉ số chính]
--   lead_days_first      = ngày nhận ĐẦU − PODate                    [cấp PO]
--   avg_line_lead_days   = TB(ReceivingDate − PODate) trên từng dòng mua
-- pay_days = PayDate − InvoiceDate.
-- =====================================================================

-- ---------- Tổng hợp dòng mua theo PO (bảng tạm dùng chung) -----------
DROP TABLE IF EXISTS temp.po_lines;
CREATE TEMP TABLE po_lines AS
SELECT PONumber,
       MIN(VendorNumber)                 AS VendorNumber,
       MIN(PODate)                       AS PODate,
       MIN(ReceivingDate)                AS FirstReceivingDate,
       MAX(ReceivingDate)                AS LastReceivingDate,
       MIN(InvoiceDate)                  AS line_InvoiceDate,     -- ngày hóa đơn ghi trên dòng mua
       MIN(PayDate)                      AS line_PayDate,
       COUNT(*)                          AS n_lines,
       COUNT(DISTINCT Brand)             AS n_brands,
       COUNT(DISTINCT Store)             AS n_stores,
       SUM(Quantity)                     AS line_qty,
       ROUND(SUM(Dollars), 2)            AS line_dollars,
       AVG(julianday(ReceivingDate) - julianday(PODate)) AS avg_line_lead_days
FROM raw.purchases
GROUP BY PONumber;
CREATE UNIQUE INDEX temp.ux_po_lines ON po_lines(PONumber);
CREATE INDEX temp.ix_po_lines_key ON po_lines(VendorNumber, line_qty, line_dollars);

-- ---------- Ghép hóa đơn ↔ PO -----------------------------------------
-- Phát hiện khi kiểm tra nhất quán: từ PONumber 12311 (PODate ≥ 2024-09-25), số PO trên
-- vendor_invoice bị XÁO TRỘN giữa các PO cùng thời điểm (NCC/số lượng/tiền không khớp PO cùng số),
-- PODate trên hóa đơn lệch ±5 ngày. NCC + số lượng + tiền thì luôn khớp đúng 1 PO.
-- ⇒ Ghép theo khóa nghiệp vụ (VendorNumber, Quantity, Dollars), ưu tiên:
--   (1) cùng PONumber và khớp khóa  → 'khớp số PO'
--   (2) cặp "gần nhất của nhau" theo |PODate hóa đơn − PODate mua| → 'ghép lại' (lặp 2 lượt)
DROP TABLE IF EXISTS map_invoice_po;
CREATE TABLE map_invoice_po (
    invoice_po        INTEGER,   -- PONumber ghi trên vendor_invoice
    PONumber          INTEGER,   -- PO thật trong purchases
    match_type        TEXT,
    podate_shift_days REAL       -- PODate(hóa đơn) − PODate(mua)
);

INSERT INTO map_invoice_po
SELECT vi.PONumber, l.PONumber, 'khớp số PO', julianday(vi.PODate) - julianday(l.PODate)
FROM raw.vendor_invoice vi
JOIN po_lines l ON l.PONumber = vi.PONumber AND l.VendorNumber = vi.VendorNumber
               AND l.line_qty = vi.Quantity AND l.line_dollars = ROUND(vi.Dollars, 2);

-- Lượt ghép lại (chạy 2 lần: lượt 2 xử lý cặp còn sót do trùng khóa)
INSERT INTO map_invoice_po
SELECT invoice_po, PONumber, 'ghép lại theo NCC+SL+tiền', shift
FROM (
    SELECT vi.PONumber AS invoice_po, l.PONumber,
           julianday(vi.PODate) - julianday(l.PODate) AS shift,
           ROW_NUMBER() OVER (PARTITION BY vi.PONumber
                              ORDER BY ABS(julianday(vi.PODate) - julianday(l.PODate)), l.PONumber) AS rn_i,
           ROW_NUMBER() OVER (PARTITION BY l.PONumber
                              ORDER BY ABS(julianday(vi.PODate) - julianday(l.PODate)), vi.PONumber) AS rn_p
    FROM raw.vendor_invoice vi
    JOIN po_lines l ON l.VendorNumber = vi.VendorNumber AND l.line_qty = vi.Quantity
                   AND l.line_dollars = ROUND(vi.Dollars, 2)
    WHERE vi.PONumber NOT IN (SELECT invoice_po FROM map_invoice_po)
      AND l.PONumber  NOT IN (SELECT PONumber  FROM map_invoice_po)
)
WHERE rn_i = 1 AND rn_p = 1;

INSERT INTO map_invoice_po
SELECT invoice_po, PONumber, 'ghép lại theo NCC+SL+tiền', shift
FROM (
    SELECT vi.PONumber AS invoice_po, l.PONumber,
           julianday(vi.PODate) - julianday(l.PODate) AS shift,
           ROW_NUMBER() OVER (PARTITION BY vi.PONumber
                              ORDER BY ABS(julianday(vi.PODate) - julianday(l.PODate)), l.PONumber) AS rn_i,
           ROW_NUMBER() OVER (PARTITION BY l.PONumber
                              ORDER BY ABS(julianday(vi.PODate) - julianday(l.PODate)), vi.PONumber) AS rn_p
    FROM raw.vendor_invoice vi
    JOIN po_lines l ON l.VendorNumber = vi.VendorNumber AND l.line_qty = vi.Quantity
                   AND l.line_dollars = ROUND(vi.Dollars, 2)
    WHERE vi.PONumber NOT IN (SELECT invoice_po FROM map_invoice_po)
      AND l.PONumber  NOT IN (SELECT PONumber  FROM map_invoice_po)
)
WHERE rn_i = 1 AND rn_p = 1;

CREATE UNIQUE INDEX ux_map_invoice_po ON map_invoice_po(PONumber);
CREATE UNIQUE INDEX ux_map_invoice_po_inv ON map_invoice_po(invoice_po);

-- ---------- 1 dòng / 1 đơn mua (PO) — 5 543 dòng ----------------------
-- Hóa đơn nối qua map_invoice_po (KHÔNG nối thẳng theo PONumber).
DROP TABLE IF EXISTS mart_po;
CREATE TABLE mart_po AS
SELECT l.PONumber, l.VendorNumber, l.PODate, l.FirstReceivingDate, l.LastReceivingDate,
       l.n_lines, l.n_brands, l.n_stores, l.line_qty, l.line_dollars, l.avg_line_lead_days,
       substr(l.PODate, 1, 7)                                        AS POMonth,
       m.invoice_po,
       m.match_type,
       m.podate_shift_days,
       vi.InvoiceDate,
       vi.PayDate,
       l.line_InvoiceDate,
       l.line_PayDate,
       vi.Quantity                                                   AS invoice_qty,
       vi.Dollars                                                    AS invoice_dollars,
       vi.Freight,
       vi.Approval IS NOT NULL                                       AS is_approved,
       julianday(l.LastReceivingDate)  - julianday(l.PODate)         AS lead_days,
       julianday(l.FirstReceivingDate) - julianday(l.PODate)         AS lead_days_first,
       julianday(vi.PayDate)  - julianday(vi.InvoiceDate)            AS pay_days,
       julianday(vi.InvoiceDate) - julianday(l.LastReceivingDate)    AS invoice_lag_days,
       vi.Freight / NULLIF(vi.Dollars, 0) * 100                      AS freight_pct,
       vi.Quantity <> l.line_qty                                     AS qty_mismatch,
       ABS(vi.Dollars - l.line_dollars) > 0.01                       AS dollar_mismatch,
       vi.InvoiceDate <> l.line_InvoiceDate                          AS invoice_date_mismatch,
       vi.PayDate <> l.line_PayDate                                  AS pay_date_mismatch
FROM po_lines l
LEFT JOIN map_invoice_po m     ON m.PONumber = l.PONumber
LEFT JOIN raw.vendor_invoice vi ON vi.PONumber = m.invoice_po;

CREATE UNIQUE INDEX ux_mart_po ON mart_po(PONumber);
CREATE INDEX ix_mart_po_vendor ON mart_po(VendorNumber);

-- ---------- Theo ngày nhận hàng × nhóm (~700 dòng) --------------------
DROP TABLE IF EXISTS mart_purchases_daily;
CREATE TABLE mart_purchases_daily AS
SELECT ReceivingDate,
       substr(ReceivingDate, 1, 7)   AS Month,
       Classification,
       COUNT(*)                      AS n_lines,
       COUNT(DISTINCT PONumber)      AS n_po,
       SUM(Quantity)                 AS qty,
       SUM(Dollars)                  AS dollars
FROM raw.purchases
GROUP BY ReceivingDate, Classification;

-- ---------- Theo cửa hàng × tháng nhận hàng ---------------------------
DROP TABLE IF EXISTS mart_purchases_store_month;
CREATE TABLE mart_purchases_store_month AS
SELECT Store,
       substr(ReceivingDate, 1, 7)   AS Month,
       Classification,
       COUNT(*)                      AS n_lines,
       SUM(Quantity)                 AS qty,
       SUM(Dollars)                  AS dollars
FROM raw.purchases
GROUP BY Store, Month, Classification;

-- ---------- Theo sản phẩm × NCC (~10 700 dòng) ------------------------
DROP TABLE IF EXISTS mart_purchases_brand;
CREATE TABLE mart_purchases_brand AS
SELECT Brand,
       VendorNumber,
       Classification,
       COUNT(*)                      AS n_lines,
       COUNT(DISTINCT PONumber)      AS n_po,
       COUNT(DISTINCT Store)         AS n_stores,
       SUM(Quantity)                 AS qty,
       SUM(Dollars)                  AS dollars,
       SUM(Dollars) / NULLIF(SUM(Quantity), 0)  AS avg_unit_cost,
       MIN(PurchasePrice)            AS min_cost,
       MAX(PurchasePrice)            AS max_cost,
       SUM(PurchasePrice = 0)        AS n_zero_cost,
       AVG(julianday(ReceivingDate) - julianday(PODate)) AS avg_line_lead_days
FROM raw.purchases
GROUP BY Brand, VendorNumber, Classification;

CREATE INDEX ix_purchases_brand ON mart_purchases_brand(Brand, VendorNumber);

-- ---------- Theo NCC × tháng nhận hàng --------------------------------
DROP TABLE IF EXISTS mart_purchases_vendor_month;
CREATE TABLE mart_purchases_vendor_month AS
SELECT VendorNumber,
       substr(ReceivingDate, 1, 7)   AS Month,
       SUM(Quantity)                 AS qty,
       SUM(Dollars)                  AS dollars
FROM raw.purchases
GROUP BY VendorNumber, Month;

-- ---------- Mẫu hệ thống 1/10 dòng (~237 000 dòng) --------------------
DROP TABLE IF EXISTS sample_purchases;
CREATE TABLE sample_purchases AS
SELECT Store, Brand, VendorNumber, Classification, PODate, ReceivingDate,
       PurchasePrice, Quantity, Dollars,
       julianday(ReceivingDate) - julianday(PODate)   AS line_lead_days,
       julianday(PayDate) - julianday(InvoiceDate)    AS pay_days
FROM raw.purchases
WHERE rowid % 10 = 0;

DROP TABLE IF EXISTS temp.po_lines;
