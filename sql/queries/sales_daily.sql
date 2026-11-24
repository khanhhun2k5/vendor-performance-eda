-- Doanh thu theo ngày (gộp 2 nhóm sản phẩm). Weekday: 0 = Chủ nhật.
SELECT SalesDate, Month, Weekday,
       SUM(n_lines) AS n_lines, SUM(qty) AS qty, SUM(dollars) AS dollars, SUM(excise) AS excise
FROM mart_sales_daily
GROUP BY SalesDate, Month, Weekday
ORDER BY SalesDate;
