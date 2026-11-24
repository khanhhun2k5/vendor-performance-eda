-- Top :top_n NCC theo doanh thu.
SELECT VendorNumber, VendorName, n_brands, sales_dollars, purchase_dollars,
       gross_profit, margin_pct, freight, freight_pct, stock_turnover,
       sales_share_pct, purchase_share_pct, cum_sales_share_pct, avg_lead_days, avg_pay_days
FROM mart_vendor
ORDER BY sales_dollars DESC
LIMIT :top_n;
