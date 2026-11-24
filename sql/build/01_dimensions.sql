-- =====================================================================
-- 01_dimensions.sql — Bảng chiều (dimension) đã làm sạch
-- Chạy trên analytics.db; staging.db (CSV gốc đã nạp) được ATTACH với tên `raw` (chỉ đọc).
-- Xử lý: strip VendorName, ép Volume sang số, điền City bị thiếu (Store 46).
-- =====================================================================

-- ---------- dim_vendor: 1 dòng / 1 mã NCC ----------------------------
DROP TABLE IF EXISTS dim_vendor;
CREATE TABLE dim_vendor AS
WITH names AS (
    SELECT VendorNumber, TRIM(VendorName) AS VendorName FROM raw.purchase_prices
    UNION ALL
    SELECT DISTINCT VendorNumber, TRIM(VendorName) FROM raw.vendor_invoice
)
SELECT VendorNumber,
       MAX(VendorName)              AS VendorName,      -- 1 mã có thể có nhiều cách viết tên
       COUNT(DISTINCT VendorName)   AS n_name_variants
FROM names
GROUP BY VendorNumber;

CREATE UNIQUE INDEX ux_dim_vendor ON dim_vendor(VendorNumber);

-- ---------- dim_product: 1 dòng / 1 Brand -----------------------------
DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product AS
SELECT Brand,
       Description,
       Size,
       CASE WHEN Volume GLOB '[0-9]*' THEN CAST(Volume AS REAL) END AS Volume,  -- 'Unknown' -> NULL
       Classification,
       CASE Classification WHEN 1 THEN 'Rượu mạnh' WHEN 2 THEN 'Rượu vang' END AS ClassName,
       Price                         AS RetailPrice,
       PurchasePrice,
       Price - PurchasePrice         AS UnitMargin,
       CASE WHEN Price > 0 THEN (Price - PurchasePrice) / Price * 100 END AS UnitMarginPct,
       VendorNumber,
       TRIM(VendorName)              AS VendorName,
       CASE
           WHEN Price <   10 THEN '1. < $10'
           WHEN Price <   20 THEN '2. $10–20'
           WHEN Price <   50 THEN '3. $20–50'
           WHEN Price <  100 THEN '4. $50–100'
           ELSE                    '5. ≥ $100'
       END                           AS PriceBand
FROM raw.purchase_prices;

CREATE UNIQUE INDEX ux_dim_product ON dim_product(Brand);
CREATE INDEX ix_dim_product_vendor ON dim_product(VendorNumber);

-- ---------- dim_store: 1 dòng / 1 cửa hàng ---------------------------
DROP TABLE IF EXISTS dim_store;
CREATE TABLE dim_store AS
WITH s AS (
    SELECT Store, City, 'begin' AS src FROM raw.begin_inventory
    UNION ALL
    SELECT Store, City, 'end'   AS src FROM raw.end_inventory
)
SELECT Store,
       MAX(City)                         AS City,            -- MAX bỏ qua NULL ⇒ điền City cho Store 46
       MAX(src = 'begin')                AS in_begin_inventory,
       MAX(src = 'end')                  AS in_end_inventory
FROM s
GROUP BY Store;

CREATE UNIQUE INDEX ux_dim_store ON dim_store(Store);
