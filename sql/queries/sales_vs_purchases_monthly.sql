-- Doanh thu bán vs chi phí mua (theo tháng nhận hàng) từng tháng.
WITH s AS (SELECT Month, SUM(dollars) AS sales_dollars, SUM(qty) AS sales_qty
           FROM mart_sales_daily GROUP BY Month),
     p AS (SELECT Month, SUM(dollars) AS purchase_dollars, SUM(qty) AS purchase_qty
           FROM mart_purchases_daily GROUP BY Month)
SELECT s.Month, s.sales_dollars, s.sales_qty, p.purchase_dollars, p.purchase_qty,
       s.sales_dollars - p.purchase_dollars           AS gap_dollars,
       s.sales_qty * 1.0 / NULLIF(p.purchase_qty, 0)  AS sell_through
FROM s LEFT JOIN p USING (Month)
ORDER BY s.Month;
