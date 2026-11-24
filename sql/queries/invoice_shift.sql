-- Độ lệch PODate (hóa đơn − dòng mua) của từng hóa đơn đã ghép lại.
SELECT invoice_po, PONumber, match_type, podate_shift_days
FROM map_invoice_po;
