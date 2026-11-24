-- =====================================================================
-- 02_sales_marts.sql — Tổng hợp bảng sales (12,8 triệu dòng) thành các
-- bảng nhỏ theo ngày / cửa hàng-tháng / sản phẩm / NCC-tháng + 1 mẫu ngẫu nhiên hệ thống.
-- Mỗi CREATE ... AS SELECT quét raw.sales đúng 1 lần (~10 s/lần).
-- =====================================================================

-- ---------- Theo ngày × nhóm sản phẩm (~730 dòng) --------------------
DROP TABLE IF EXISTS mart_sales_daily;
CREATE TABLE mart_sales_daily AS
SELECT SalesDate,
       substr(SalesDate, 1, 7)                       AS Month,
       CAST(strftime('%w', SalesDate) AS INTEGER)    AS Weekday,      -- 0 = Chủ nhật
       Classification,
       COUNT(*)                                      AS n_lines,
       SUM(SalesQuantity)                            AS qty,
       SUM(SalesDollars)                             AS dollars,
       SUM(ExciseTax)                                AS excise,
       SUM(SalesQuantity * Volume) / 1000.0          AS liters
FROM raw.sales
GROUP BY SalesDate, Classification;

CREATE INDEX ix_sales_daily ON mart_sales_daily(SalesDate);

-- ---------- Theo cửa hàng × tháng × nhóm (~1 900 dòng) ---------------
DROP TABLE IF EXISTS mart_sales_store_month;
CREATE TABLE mart_sales_store_month AS
SELECT Store,
       substr(SalesDate, 1, 7)       AS Month,
       Classification,
       COUNT(*)                      AS n_lines,
       COUNT(DISTINCT Brand)         AS n_brands,
       SUM(SalesQuantity)            AS qty,
       SUM(SalesDollars)             AS dollars,
       SUM(ExciseTax)                AS excise
FROM raw.sales
GROUP BY Store, Month, Classification;

CREATE INDEX ix_sales_store_month ON mart_sales_store_month(Store, Month);

-- ---------- Theo sản phẩm (~11 000 dòng) ------------------------------
DROP TABLE IF EXISTS mart_sales_brand;
CREATE TABLE mart_sales_brand AS
SELECT Brand,
       VendorNo                      AS VendorNumber,   -- chuẩn hóa tên cột
       Classification,
       MAX(Volume)                   AS Volume,
       COUNT(*)                      AS n_lines,
       COUNT(DISTINCT Store)         AS n_stores,
       COUNT(DISTINCT SalesDate)     AS n_days,
       SUM(SalesQuantity)            AS qty,
       SUM(SalesDollars)             AS dollars,
       SUM(ExciseTax)                AS excise,
       SUM(SalesDollars) / NULLIF(SUM(SalesQuantity), 0) AS avg_unit_price,
       MIN(SalesPrice)               AS min_price,
       MAX(SalesPrice)               AS max_price,
       SUM(SalesPrice = 0)           AS n_zero_price
FROM raw.sales
GROUP BY Brand, VendorNo, Classification;

CREATE INDEX ix_sales_brand ON mart_sales_brand(Brand);
CREATE INDEX ix_sales_brand_vendor ON mart_sales_brand(VendorNumber);

-- ---------- Theo NCC × tháng (~1 500 dòng) ----------------------------
DROP TABLE IF EXISTS mart_sales_vendor_month;
CREATE TABLE mart_sales_vendor_month AS
SELECT VendorNo                      AS VendorNumber,
       substr(SalesDate, 1, 7)       AS Month,
       SUM(SalesQuantity)            AS qty,
       SUM(SalesDollars)             AS dollars,
       SUM(ExciseTax)                AS excise
FROM raw.sales
GROUP BY VendorNo, Month;

CREATE INDEX ix_sales_vendor_month ON mart_sales_vendor_month(VendorNumber, Month);

-- ---------- Mẫu hệ thống 1/50 dòng (~256 000 dòng) cho biểu đồ phân phối
-- rowid % 50 = 0 cho kết quả tái lập được (không phụ thuộc seed).
DROP TABLE IF EXISTS sample_sales;
CREATE TABLE sample_sales AS
SELECT Store, Brand, Classification, SalesDate,
       SalesQuantity, SalesDollars, SalesPrice, Volume, ExciseTax,
       ExciseTax / NULLIF(SalesQuantity * Volume / 1000.0, 0) AS excise_per_liter
FROM raw.sales
WHERE rowid % 50 = 0;
