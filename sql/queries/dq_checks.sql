-- Danh sách vấn đề chất lượng dữ liệu kèm tỷ lệ ảnh hưởng.
SELECT check_id, check_name, table_name,
       CAST(n_affected AS INTEGER)               AS n_affected,
       CAST(n_total AS INTEGER)                  AS n_total,
       n_affected * 100.0 / NULLIF(n_total, 0)   AS affected_pct,
       action
FROM dq_checks
ORDER BY check_id, table_name;
