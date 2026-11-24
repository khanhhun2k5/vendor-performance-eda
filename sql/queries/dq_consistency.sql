-- Kiểm tra nhất quán giữa các file CSV (nhóm, số vi phạm, mức độ). Lọc :severity = '*' hoặc 'Lỗi'/'Cảnh báo'/'Đạt'.
SELECT check_group, check_name, tables,
       CAST(n_affected AS INTEGER)              AS n_affected,
       CAST(n_total AS INTEGER)                 AS n_total,
       n_affected * 100.0 / NULLIF(n_total, 0)  AS affected_pct,
       severity, note
FROM dq_consistency
WHERE :severity = '*' OR severity = :severity
ORDER BY CASE severity WHEN 'Lỗi' THEN 0 WHEN 'Cảnh báo' THEN 1 ELSE 2 END, check_group;
