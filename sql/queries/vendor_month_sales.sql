-- Doanh thu theo tháng của top :top_n NCC (dạng dài).
SELECT s.VendorNumber, v.VendorName, v.sales_rank, s.Month, s.dollars
FROM mart_sales_vendor_month s
JOIN mart_vendor v USING (VendorNumber)
WHERE v.sales_rank <= :top_n
ORDER BY v.sales_rank, s.Month;
