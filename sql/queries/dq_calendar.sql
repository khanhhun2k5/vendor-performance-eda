-- Lịch 366 ngày năm 2024: có dữ liệu bán / nhận hàng hay không, doanh thu và tiền nhận hàng mỗi ngày.
SELECT day, weekday, has_sales, has_receiving, sales_dollars, receiving_dollars
FROM dq_calendar
ORDER BY day;
