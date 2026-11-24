-- =====================================================================
-- profile_table.sql — Template profiling 1 bảng gốc trong 1 lần quét.
-- Python (src/data_loader.py::build_profile) thay:
--   {table}         : tên bảng trong raw
--   {column_exprs}  : các đoạn profile_column.sql nối bằng dấu phẩy
-- Kết quả 1 dòng (rộng) được chuyển thành bảng dọc profile_columns.
-- =====================================================================
SELECT COUNT(*) AS n_rows,
       {column_exprs}
FROM raw."{table}"
