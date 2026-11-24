-- Sản phẩm vòng quay (SL bán / SL mua) < :max_turnover, xếp theo giá vốn hàng chưa bán ước tính
-- = (SL mua − SL bán) × giá mua bình quân THỰC TẾ (purchase_dollars / purchase_qty).
SELECT Brand, Description, VendorName, ClassName, RetailPrice, PurchasePrice,
       purchase_qty, sales_qty, purchase_dollars, sales_dollars, stock_turnover,
       (purchase_qty - sales_qty) * purchase_dollars / NULLIF(purchase_qty, 0) AS unsold_cost_est
FROM mart_vendor_brand
WHERE stock_turnover < :max_turnover
ORDER BY unsold_cost_est DESC
LIMIT :top_n;
