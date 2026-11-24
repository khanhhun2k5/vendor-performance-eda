-- Số mặt hàng theo trạng thái tồn kho × nhóm sản phẩm.
SELECT status, Classification,
       COUNT(*)          AS n_items,
       SUM(begin_onhand) AS begin_units, SUM(end_onhand) AS end_units,
       SUM(begin_value)  AS begin_value, SUM(end_value)  AS end_value
FROM mart_inventory
GROUP BY status, Classification
ORDER BY status, Classification;
