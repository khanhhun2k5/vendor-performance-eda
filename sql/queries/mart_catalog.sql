-- Danh mục bảng trong analytics.db (dim_*, mart_*, sample_*, profile, dq) và số dòng.
SELECT name AS table_name
FROM sqlite_master
WHERE type = 'table'
ORDER BY name;
