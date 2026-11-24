-- Hồ sơ các cột ngày: định dạng sai, min/max, số ngày khác nhau, số dòng ngoài năm 2024.
SELECT table_name, column_name, n_rows, n_null, n_bad_format, min_date, max_date,
       n_distinct_days, n_before_2024, n_after_2024,
       (n_before_2024 + n_after_2024) * 100.0 / n_rows AS outside_2024_pct
FROM dq_dates
ORDER BY table_name, column_name;
