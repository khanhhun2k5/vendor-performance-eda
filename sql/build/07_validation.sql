-- =====================================================================
-- 07_validation.sql — KIỂM CHỨNG (không phải nguồn dữ liệu).
-- So các mart tự dựng từ CSV gốc với bảng tham chiếu raw.ref_vendor_sales_summary
-- (nạp từ vendor_sales_summary.csv). Không bảng mart/dim nào phụ thuộc file này.
-- =====================================================================

-- ---------- Bản sạch của bảng tham chiếu --------------------------------
DROP TABLE IF EXISTS vss_clean;
CREATE TABLE vss_clean AS
SELECT VendorNumber, TRIM(VendorName) AS VendorName, Brand, Description,
       PurchasePrice, ActualPrice, Volume,
       TotalPurchaseQuantity, TotalPurchaseDollars,
       TotalSalesQuantity, TotalSalesDollars, TotalExciseTax,
       FreightCost, GrossProfit,
       CASE WHEN ProfitMargin BETWEEN -1e300 AND 1e300 THEN ProfitMargin END AS ProfitMargin,  -- -inf → NULL
       StockTurnover, SalestoPurchaseRatio
FROM raw.ref_vendor_sales_summary;

CREATE INDEX ix_vss_clean ON vss_clean(VendorNumber, Brand);

-- ---------- Ghi kết quả kiểm chứng vào dq_checks ------------------------
INSERT INTO dq_checks
SELECT 9, '[Tham chiếu] ProfitMargin = −inf trong vendor_sales_summary', 'vendor_sales_summary',
       SUM(ProfitMargin IS NULL), COUNT(*), 'Chỉ đối chiếu — mart tự tính dùng NULL'
FROM vss_clean;

INSERT INTO dq_checks
SELECT 14, '[Kiểm chứng] mart_vendor_brand lệch vendor_sales_summary (doanh thu > $0,01)', 'vss_clean',
       SUM(ABS(v.TotalSalesDollars - m.sales_dollars) > 0.01), COUNT(*), 'Kỳ vọng = 0'
FROM vss_clean v
JOIN mart_vendor_brand m ON m.VendorNumber = v.VendorNumber AND m.Brand = v.Brand;

-- Anti-join 2 chiều: dòng có ở một bên mà không có ở bên kia (INNER JOIN ở trên không thấy được)
INSERT INTO dq_checks
SELECT 14, '[Kiểm chứng] Cặp có mua trong mart nhưng thiếu trong vendor_sales_summary', 'mart_vendor_brand',
       COUNT(*), (SELECT SUM(has_purchase) FROM mart_vendor_brand), 'Giải thích từng dòng'
FROM mart_vendor_brand m
WHERE m.has_purchase
  AND NOT EXISTS (SELECT 1 FROM vss_clean v WHERE v.VendorNumber = m.VendorNumber AND v.Brand = m.Brand);

INSERT INTO dq_checks
SELECT 14, '[Kiểm chứng] Cặp trong vendor_sales_summary nhưng thiếu trong mart', 'vss_clean',
       COUNT(*), (SELECT COUNT(*) FROM vss_clean), 'Kỳ vọng = 0'
FROM vss_clean v
WHERE NOT EXISTS (SELECT 1 FROM mart_vendor_brand m WHERE m.VendorNumber = v.VendorNumber AND m.Brand = v.Brand);

-- Phí vận chuyển theo NCC: mart (hóa đơn đã ghép lại) vs FreightCost của bảng tham chiếu
INSERT INTO dq_checks
SELECT 14, '[Kiểm chứng] Phí vận chuyển theo NCC lệch FreightCost của vendor_sales_summary', 'mart_vendor_po',
       SUM(ABS(r.fc - COALESCE(vp.freight, 0)) > 0.01), COUNT(*), 'Kỳ vọng = 0'
FROM (SELECT VendorNumber, MAX(FreightCost) AS fc FROM vss_clean GROUP BY VendorNumber) r
LEFT JOIN mart_vendor_po vp USING (VendorNumber);
