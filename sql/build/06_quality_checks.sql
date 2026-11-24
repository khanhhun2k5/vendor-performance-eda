-- =====================================================================
-- 06_quality_checks.sql — Bảng dq_checks: mỗi dòng = 1 vấn đề chất lượng
-- dữ liệu (đánh số theo §4 của data/data_dictionary.md) + số dòng bị ảnh hưởng.
-- Phần đếm trên bảng lớn tận dụng mart đã có để tránh quét lại.
-- =====================================================================

DROP TABLE IF EXISTS dq_checks;
CREATE TABLE dq_checks (
    check_id     INTEGER,
    check_name   TEXT,
    table_name   TEXT,
    n_affected   REAL,
    n_total      REAL,
    action       TEXT
);

INSERT INTO dq_checks
SELECT 1, 'VendorName có khoảng trắng thừa', 'purchase_prices',
       SUM(VendorName <> TRIM(VendorName)), COUNT(*), 'TRIM()'
FROM raw.purchase_prices;

INSERT INTO dq_checks
SELECT 1, 'VendorName có khoảng trắng thừa', 'vendor_invoice',
       SUM(VendorName <> TRIM(VendorName)), COUNT(*), 'TRIM()'
FROM raw.vendor_invoice;

INSERT INTO dq_checks
SELECT 1, '1 mã NCC có nhiều cách viết tên', 'dim_vendor',
       SUM(n_name_variants > 1), COUNT(*), 'Lấy 1 tên chuẩn theo VendorNumber'
FROM dim_vendor;

INSERT INTO dq_checks
SELECT 4, 'Volume không phải số (Unknown/NULL)', 'purchase_prices',
       SUM(Volume IS NULL OR Volume NOT GLOB '[0-9]*'), COUNT(*), 'Ép kiểu số, lỗi → NULL'
FROM raw.purchase_prices;

INSERT INTO dq_checks
SELECT 5, 'City bị thiếu', 'end_inventory',
       SUM(City IS NULL), COUNT(*), 'Điền theo Store từ begin_inventory'
FROM raw.end_inventory;

INSERT INTO dq_checks
SELECT 6, 'PurchasePrice = 0', 'purchases',
       SUM(n_zero_cost), SUM(n_lines), 'Gắn cờ / loại khi tính giá vốn'
FROM mart_purchases_brand;

INSERT INTO dq_checks
SELECT 6, 'SalesPrice = 0', 'sales',
       SUM(n_zero_price), SUM(n_lines), 'Gắn cờ / loại khi tính giá bán'
FROM mart_sales_brand;

INSERT INTO dq_checks
SELECT 6, 'Price = 0 (danh mục)', 'purchase_prices',
       SUM(Price = 0), COUNT(*), 'Gắn cờ'
FROM raw.purchase_prices;

INSERT INTO dq_checks
SELECT 7, 'Approval rỗng', 'vendor_invoice',
       SUM(Approval IS NULL), COUNT(*), 'Coi là “chưa ghi nhận”, không impute'
FROM raw.vendor_invoice;

INSERT INTO dq_checks
SELECT 8, 'Số PO trên hóa đơn bị xáo trộn (ghép lại theo NCC+SL+tiền)', 'vendor_invoice',
       SUM(match_type <> 'khớp số PO'), COUNT(*), 'Nối hóa đơn qua map_invoice_po, không theo PONumber'
FROM map_invoice_po;

INSERT INTO dq_checks
SELECT 8, 'Hóa đơn không ghép được với PO nào', 'vendor_invoice',
       (SELECT COUNT(*) FROM raw.vendor_invoice) - (SELECT COUNT(*) FROM map_invoice_po),
       (SELECT COUNT(*) FROM raw.vendor_invoice), 'Kỳ vọng = 0'
;

INSERT INTO dq_checks
SELECT 8, 'Sau ghép: SL/tiền hóa đơn ≠ tổng dòng mua', 'mart_po',
       SUM(qty_mismatch OR dollar_mismatch), COUNT(*), 'Kỳ vọng = 0'
FROM mart_po;

INSERT INTO dq_checks
SELECT 8, 'Sau ghép: InvoiceDate hóa đơn ≠ InvoiceDate trên dòng mua', 'mart_po',
       SUM(invoice_date_mismatch), COUNT(*), 'pay_days tính theo ngày trên hóa đơn'
FROM mart_po;

INSERT INTO dq_checks
SELECT 8, 'Sau ghép: PayDate hóa đơn ≠ PayDate trên dòng mua', 'mart_po',
       SUM(pay_date_mismatch), COUNT(*), 'pay_days tính theo ngày trên hóa đơn'
FROM mart_po;

INSERT INTO dq_checks
SELECT 10, 'GrossProfit < 0 (lỗ gộp)', 'mart_vendor_brand',
       SUM(gross_profit < 0), COUNT(*), 'Không phải lỗi — phân tích riêng'
FROM mart_vendor_brand;

INSERT INTO dq_checks
SELECT 10, 'Sản phẩm đã mua nhưng không bán được', 'mart_vendor_brand',
       SUM(sales_qty = 0), COUNT(*), 'Ứng viên hàng tồn chậm'
FROM mart_vendor_brand;

INSERT INTO dq_checks
SELECT 13, 'PODate trước 2024', 'purchases (PO)',
       SUM(PODate < '2024-01-01'), COUNT(*), 'Hợp lệ (đơn vắt kỳ)'
FROM mart_po;

INSERT INTO dq_checks
SELECT 13, 'PayDate sang 2025', 'vendor_invoice',
       SUM(PayDate >= '2025-01-01'), COUNT(*), 'Hợp lệ (đơn vắt kỳ)'
FROM mart_po;

INSERT INTO dq_checks
SELECT 15, 'Cặp (Brand, NCC) có bán nhưng không có dòng mua trong kỳ', 'mart_vendor_brand',
       SUM(NOT has_purchase), COUNT(*), 'Giữ lại (FULL JOIN) — bán từ tồn đầu kỳ'
FROM mart_vendor_brand;
