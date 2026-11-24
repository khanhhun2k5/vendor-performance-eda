-- Doanh thu trung bình/ngày theo thứ trong tuần (0 = Chủ nhật).
WITH daily AS (
    SELECT SalesDate, Weekday, SUM(dollars) AS dollars, SUM(qty) AS qty
    FROM mart_sales_daily
    GROUP BY SalesDate, Weekday
)
SELECT Weekday, COUNT(*) AS n_days,
       AVG(dollars) AS avg_dollars, AVG(qty) AS avg_qty,
       MIN(dollars) AS min_dollars, MAX(dollars) AS max_dollars
FROM daily
GROUP BY Weekday
ORDER BY Weekday;
