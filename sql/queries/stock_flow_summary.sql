-- Cân đối tồn kho: tổng đầu kỳ, mua, bán, cuối kỳ, lệch — theo nhóm có/không có trong ảnh chụp tồn kho.
SELECT CASE WHEN not_in_snapshots THEN 'Không có trong ảnh chụp tồn kho' ELSE 'Có trong ảnh chụp tồn kho' END AS item_group,
       COUNT(*) AS n_items,
       SUM(begin_onhand) AS begin_onhand, SUM(purchased) AS purchased, SUM(sold) AS sold,
       SUM(end_onhand) AS end_onhand, SUM(gap) AS gap, SUM(gap <> 0) AS n_items_gap
FROM mart_stock_flow
GROUP BY 1;
