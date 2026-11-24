-- KPI toàn bộ NCC (có cột Pareto). Lọc NCC có doanh thu >= :min_sales.
SELECT *
FROM mart_vendor
WHERE COALESCE(sales_dollars, 0) >= :min_sales
ORDER BY sales_rank;
