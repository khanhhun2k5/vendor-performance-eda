-- Đoạn biểu thức cho 1 cột ({col}, chỉ số {i}). Dùng bên trong profile_table.sql.
SUM("{col}" IS NULL)                          AS c{i}_n_null,
COUNT(DISTINCT "{col}")                       AS c{i}_n_distinct,
SUM(typeof("{col}") IN ('integer','real') AND "{col}" = 0) AS c{i}_n_zero,
SUM(typeof("{col}") = 'text' AND "{col}" <> TRIM("{col}")) AS c{i}_n_untrimmed,
MIN("{col}")                                  AS c{i}_min,
MAX("{col}")                                  AS c{i}_max,
AVG(CASE WHEN typeof("{col}") IN ('integer','real') THEN "{col}" END) AS c{i}_mean
