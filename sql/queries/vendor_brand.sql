-- Bảng NCC × sản phẩm (cấp phân tích chính). Lọc tiền mua >= :min_purchase.
SELECT *
FROM mart_vendor_brand
WHERE purchase_dollars >= :min_purchase;
