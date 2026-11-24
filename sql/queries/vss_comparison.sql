-- [Kiểm chứng] Đối chiếu mart_vendor_brand (tự tính từ CSV gốc) với vendor_sales_summary.csv (chỉ tham chiếu).
SELECT COUNT(*)                                                       AS n_matched,
       SUM(ABS(v.TotalPurchaseDollars - m.purchase_dollars) > 0.01)   AS n_purchase_diff,
       SUM(ABS(v.TotalSalesDollars    - m.sales_dollars)    > 0.01)   AS n_sales_diff,
       SUM(ABS(v.TotalSalesQuantity   - m.sales_qty)        > 0.01)   AS n_sales_qty_diff,
       SUM(ABS(v.GrossProfit          - m.gross_profit)     > 0.01)   AS n_gross_profit_diff,
       (SELECT COUNT(*) FROM vss_clean)                               AS n_vss_rows,
       (SELECT SUM(has_purchase) FROM mart_vendor_brand)              AS n_mart_rows_with_purchase,
       (SELECT SUM(NOT has_purchase) FROM mart_vendor_brand)          AS n_mart_rows_sales_only
FROM vss_clean v
JOIN mart_vendor_brand m ON m.VendorNumber = v.VendorNumber AND m.Brand = v.Brand;
