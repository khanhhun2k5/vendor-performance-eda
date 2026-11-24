-- Doanh thu & số lượng bán theo tháng × nhóm sản phẩm.
SELECT Month, Classification,
       CASE Classification WHEN 1 THEN 'Rượu mạnh' ELSE 'Rượu vang' END AS ClassName,
       SUM(n_lines) AS n_lines, SUM(qty) AS qty, SUM(dollars) AS dollars,
       SUM(excise)  AS excise,  SUM(liters) AS liters
FROM mart_sales_daily
GROUP BY Month, Classification
ORDER BY Month, Classification;
