-- KPI theo phân khúc giá bán lẻ niêm yết.
SELECT PriceBand,
       COUNT(*)                                                 AS n_brands,
       SUM(sales_qty)                                           AS sales_qty,
       SUM(sales_dollars)                                       AS sales_dollars,
       SUM(gross_profit)                                        AS gross_profit,
       SUM(gross_profit) / NULLIF(SUM(sales_dollars), 0) * 100  AS margin_pct,
       SUM(sales_qty) * 1.0 / NULLIF(SUM(purchase_qty), 0)      AS stock_turnover,
       SUM(sales_qty = 0)                                       AS n_unsold
FROM mart_vendor_brand
WHERE PriceBand IS NOT NULL
GROUP BY PriceBand
ORDER BY PriceBand;
