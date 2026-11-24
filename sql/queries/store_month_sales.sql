-- Doanh thu cửa hàng × tháng (dạng dài, pivot bằng pandas).
SELECT Store, Month, SUM(dollars) AS dollars, SUM(qty) AS qty
FROM mart_sales_store_month
GROUP BY Store, Month
ORDER BY Store, Month;
