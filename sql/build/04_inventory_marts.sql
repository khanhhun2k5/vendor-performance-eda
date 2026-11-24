-- =====================================================================
-- 04_inventory_marts.sql — So sánh tồn kho đầu kỳ (01/01) và cuối kỳ (31/12).
-- FULL OUTER JOIN theo InventoryId (cần SQLite ≥ 3.39).
-- Bảng gốc không có index ⇒ chép sang bảng TEMP có index trước khi join,
-- nếu không FULL JOIN sẽ so từng cặp (~4,6·10^10 phép so sánh).
-- =====================================================================

DROP TABLE IF EXISTS temp.b_inv;
CREATE TEMP TABLE b_inv AS
SELECT InventoryId, Store, Brand, onHand, Price FROM raw.begin_inventory;
CREATE UNIQUE INDEX temp.ux_b_inv ON b_inv(InventoryId);

DROP TABLE IF EXISTS temp.e_inv;
CREATE TEMP TABLE e_inv AS
SELECT InventoryId, Store, Brand, onHand, Price FROM raw.end_inventory;
CREATE UNIQUE INDEX temp.ux_e_inv ON e_inv(InventoryId);

DROP TABLE IF EXISTS mart_inventory;
CREATE TABLE mart_inventory AS
SELECT COALESCE(b.InventoryId, e.InventoryId)    AS InventoryId,
       COALESCE(b.Store, e.Store)                AS Store,
       COALESCE(b.Brand, e.Brand)                AS Brand,
       p.Classification,
       COALESCE(b.onHand, 0)                     AS begin_onhand,
       COALESCE(e.onHand, 0)                     AS end_onhand,
       b.Price                                   AS begin_price,
       e.Price                                   AS end_price,
       COALESCE(b.onHand * b.Price, 0)           AS begin_value,
       COALESCE(e.onHand * e.Price, 0)           AS end_value,
       COALESCE(e.onHand, 0) - COALESCE(b.onHand, 0) AS delta_onhand,
       CASE
           WHEN b.InventoryId IS NULL THEN 'Chỉ có cuối kỳ (mới)'
           WHEN e.InventoryId IS NULL THEN 'Chỉ có đầu kỳ (ngừng)'
           ELSE 'Có cả hai kỳ'
       END                                       AS status
FROM temp.b_inv b
FULL OUTER JOIN temp.e_inv e ON e.InventoryId = b.InventoryId
LEFT JOIN dim_product p ON p.Brand = COALESCE(b.Brand, e.Brand);

CREATE INDEX ix_mart_inventory_store ON mart_inventory(Store);
CREATE INDEX ix_mart_inventory_brand ON mart_inventory(Brand);

-- ---------- Tổng hợp tồn kho theo cửa hàng (~80 dòng) -----------------
DROP TABLE IF EXISTS mart_inventory_store;
CREATE TABLE mart_inventory_store AS
SELECT i.Store,
       s.City,
       COUNT(*)                                  AS n_items,
       SUM(i.begin_onhand)                       AS begin_units,
       SUM(i.end_onhand)                         AS end_units,
       SUM(i.begin_value)                        AS begin_value,
       SUM(i.end_value)                          AS end_value,
       SUM(i.status = 'Chỉ có cuối kỳ (mới)')    AS n_new_items,
       SUM(i.status = 'Chỉ có đầu kỳ (ngừng)')   AS n_dropped_items
FROM mart_inventory i
LEFT JOIN dim_store s USING (Store)
GROUP BY i.Store, s.City;

DROP TABLE IF EXISTS temp.b_inv;
DROP TABLE IF EXISTS temp.e_inv;
