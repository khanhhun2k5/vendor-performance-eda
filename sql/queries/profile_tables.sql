-- Tổng quan các bảng gốc: số dòng, số cột, tổng ô null. Nguồn: profile_columns.
SELECT table_name,
       MAX(n_rows)                                          AS n_rows,
       COUNT(*)                                             AS n_columns,
       SUM(n_null)                                          AS n_null_cells,
       SUM(n_null) * 100.0 / (MAX(n_rows) * COUNT(*))       AS null_cell_pct,
       SUM(n_untrimmed > 0)                                 AS n_cols_untrimmed
FROM profile_columns
GROUP BY table_name
ORDER BY n_rows DESC;
