-- Tồn kho đầu/cuối kỳ cấp InventoryId (chỉ cột số để nhẹ bộ nhớ).
SELECT Store, Brand, Classification, status,
       begin_onhand, end_onhand, begin_value, end_value, delta_onhand
FROM mart_inventory;
