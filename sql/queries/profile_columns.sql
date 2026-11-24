-- Hồ sơ từng cột của 1 bảng (:table) hoặc tất cả bảng khi :table = '*'.
SELECT table_name, ordinal, column_name, declared_type,
       n_rows, n_null, null_pct, n_distinct, distinct_pct,
       n_zero, n_untrimmed, min_value, max_value, mean_value
FROM profile_columns
WHERE :table = '*' OR table_name = :table
ORDER BY table_name, ordinal;
