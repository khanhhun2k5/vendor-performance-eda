-- So sánh 2 nhóm sản phẩm: số SP, doanh thu, tiền mua, lợi nhuận gộp, biên, vòng quay.
SELECT Classification, ClassName,
       COUNT(*)                                                 AS n_brands,
       SUM(purchase_dollars)                                    AS purchase_dollars,
       SUM(sales_dollars)                                       AS sales_dollars,
       SUM(gross_profit)                                        AS gross_profit,
       SUM(gross_profit) / NULLIF(SUM(sales_dollars), 0) * 100  AS margin_pct,
       SUM(sales_qty) * 1.0 / NULLIF(SUM(purchase_qty), 0)      AS stock_turnover,
       SUM(excise)                                              AS excise
FROM mart_vendor_brand
GROUP BY Classification, ClassName
ORDER BY Classification;
