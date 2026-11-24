-- Kết quả ghép hóa đơn ↔ PO: loại ghép, độ lệch PODate, theo tháng đặt hàng.
SELECT p.POMonth, m.match_type, COUNT(*) AS n_po,
       AVG(m.podate_shift_days) AS avg_shift, MIN(m.podate_shift_days) AS min_shift,
       MAX(m.podate_shift_days) AS max_shift,
       SUM(p.invoice_date_mismatch) AS n_invoice_date_diff, SUM(p.pay_date_mismatch) AS n_pay_date_diff
FROM map_invoice_po m
JOIN mart_po p USING (PONumber)
GROUP BY p.POMonth, m.match_type
ORDER BY p.POMonth, m.match_type;
