-- 1 dòng / PO: thời gian giao, thanh toán, phí vận chuyển, cờ lệch hóa đơn.
SELECT p.*, v.VendorName
FROM mart_po p
LEFT JOIN dim_vendor v USING (VendorNumber);
