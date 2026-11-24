-- Sản phẩm doanh thu thấp (phân vị <= :sales_pct) nhưng biên cao (phân vị >= :margin_pct)
-- => ứng viên khuyến mãi / tăng trưng bày.
WITH ranked AS (
    SELECT *,
           PERCENT_RANK() OVER (ORDER BY sales_dollars) AS sales_prank,
           PERCENT_RANK() OVER (ORDER BY margin_pct)    AS margin_prank
    FROM mart_vendor_brand
    WHERE sales_dollars > 0 AND purchase_dollars > 0 AND margin_pct IS NOT NULL   -- loại giá mua = 0 (biên 100 % giả)
)
SELECT Brand, Description, VendorName, ClassName, RetailPrice,
       sales_dollars, gross_profit, margin_pct, stock_turnover, sales_prank, margin_prank
FROM ranked
WHERE sales_prank <= :sales_pct AND margin_prank >= :margin_pct
ORDER BY margin_pct DESC;
