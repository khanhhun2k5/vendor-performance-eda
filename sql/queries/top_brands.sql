-- Top :top_n sản phẩm theo doanh thu, kèm biên và vòng quay.
SELECT Brand, Description, VendorName, ClassName, RetailPrice,
       sales_qty, sales_dollars, purchase_dollars, gross_profit, margin_pct,
       stock_turnover, n_stores_sold
FROM mart_vendor_brand
ORDER BY sales_dollars DESC
LIMIT :top_n;
