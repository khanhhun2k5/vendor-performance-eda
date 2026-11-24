-- KPI theo cửa hàng: doanh thu, tiền mua, tồn kho đầu/cuối kỳ.
WITH s AS (SELECT Store, SUM(dollars) AS sales_dollars, SUM(qty) AS sales_qty,
                  MAX(n_brands) AS max_brands_month
           FROM mart_sales_store_month GROUP BY Store),
     p AS (SELECT Store, SUM(dollars) AS purchase_dollars, SUM(qty) AS purchase_qty
           FROM mart_purchases_store_month GROUP BY Store)
SELECT st.Store, st.City, s.sales_dollars, s.sales_qty, s.max_brands_month,
       p.purchase_dollars, p.purchase_qty,
       i.n_items, i.begin_value, i.end_value, i.begin_units, i.end_units,
       s.sales_dollars / NULLIF((i.begin_value + i.end_value) / 2.0, 0) AS sales_to_avg_inventory
FROM dim_store st
LEFT JOIN s USING (Store)
LEFT JOIN p USING (Store)
LEFT JOIN mart_inventory_store i USING (Store)
ORDER BY s.sales_dollars DESC;
