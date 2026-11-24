-- =====================================================================
-- 05_vendor_marts.sql — KPI theo NCC × sản phẩm và theo NCC.
-- Dựng lại từ các mart ở bước 02–03 (không quét lại bảng gốc lớn).
-- Phí vận chuyển ở cấp NCC được PHÂN BỔ cho sản phẩm theo tỷ trọng tiền mua.
-- mart_vendor_brand dùng FULL JOIN mua ⟗ bán ⇒ giữ cả cặp (Brand, NCC) chỉ có bán
-- (không có dòng mua trong kỳ, has_purchase = 0) để tổng doanh thu khớp mart_sales_*.
-- stock_turnover = SL bán / SL mua (tỷ lệ bán/mua – sell-through), không phải vòng quay kế toán.
-- =====================================================================

-- ---------- Phí vận chuyển & thời gian theo NCC (từ mart_po) ----------
DROP TABLE IF EXISTS mart_vendor_po;
CREATE TABLE mart_vendor_po AS
SELECT VendorNumber,
       COUNT(*)                        AS n_po,
       SUM(Freight)                    AS freight,
       SUM(invoice_dollars)            AS invoice_dollars,
       AVG(lead_days)                  AS avg_lead_days,
       AVG(pay_days)                   AS avg_pay_days,
       AVG(freight_pct)                AS avg_freight_pct,
       AVG(is_approved) * 100          AS approved_pct
FROM mart_po
GROUP BY VendorNumber;

-- ---------- NCC × sản phẩm (~10 700 dòng) -----------------------------
DROP TABLE IF EXISTS mart_vendor_brand;
CREATE TABLE mart_vendor_brand AS
WITH pur AS (
    SELECT Brand, VendorNumber,
           SUM(qty) AS purchase_qty, SUM(dollars) AS purchase_dollars,
           SUM(n_zero_cost) AS n_zero_cost, AVG(avg_line_lead_days) AS avg_line_lead_days
    FROM mart_purchases_brand
    GROUP BY Brand, VendorNumber
),
sal AS (
    SELECT Brand, VendorNumber,
           SUM(qty) AS sales_qty, SUM(dollars) AS sales_dollars,
           SUM(excise) AS excise, MAX(n_stores) AS n_stores_sold
    FROM mart_sales_brand
    GROUP BY Brand, VendorNumber
),
keys AS (                                     -- hợp các cặp có mua HOẶC có bán
    SELECT Brand, VendorNumber FROM pur
    UNION
    SELECT Brand, VendorNumber FROM sal
),
vendor_total AS (
    SELECT VendorNumber, SUM(purchase_dollars) AS vendor_purchase_dollars
    FROM pur GROUP BY VendorNumber
)
SELECT k.VendorNumber,
       v.VendorName,
       k.Brand,
       p.Description,
       p.Classification,
       p.ClassName,
       p.PriceBand,
       p.RetailPrice,
       p.PurchasePrice,
       p.Volume,
       (pur.Brand IS NOT NULL)           AS has_purchase,
       COALESCE(pur.purchase_qty, 0)     AS purchase_qty,
       COALESCE(pur.purchase_dollars, 0) AS purchase_dollars,
       COALESCE(sal.sales_qty, 0)        AS sales_qty,
       COALESCE(sal.sales_dollars, 0)    AS sales_dollars,
       COALESCE(sal.excise, 0)           AS excise,
       sal.n_stores_sold,
       pur.avg_line_lead_days,
       COALESCE(pur.n_zero_cost, 0)      AS n_zero_cost,
       COALESCE(vp.freight, 0) * COALESCE(pur.purchase_dollars, 0)
           / NULLIF(vt.vendor_purchase_dollars, 0)                   AS freight_alloc,
       COALESCE(sal.sales_dollars, 0) - COALESCE(pur.purchase_dollars, 0) AS gross_profit,
       CASE WHEN pur.Brand IS NOT NULL                                -- không có dòng mua ⇒ không có giá vốn
            THEN (COALESCE(sal.sales_dollars, 0) - pur.purchase_dollars)
                 / NULLIF(sal.sales_dollars, 0) * 100 END            AS margin_pct,   -- NULL thay cho -inf / 100 % giả
       COALESCE(sal.sales_dollars, 0) - COALESCE(pur.purchase_dollars, 0)
           - COALESCE(vp.freight, 0) * COALESCE(pur.purchase_dollars, 0)
             / NULLIF(vt.vendor_purchase_dollars, 0)                 AS net_profit_est,
       COALESCE(sal.sales_qty, 0) * 1.0 / NULLIF(pur.purchase_qty, 0)  AS stock_turnover,
       COALESCE(sal.sales_dollars, 0) / NULLIF(pur.purchase_dollars, 0) AS sales_to_purchase
FROM keys k
LEFT JOIN pur           ON pur.Brand = k.Brand AND pur.VendorNumber = k.VendorNumber
LEFT JOIN sal           ON sal.Brand = k.Brand AND sal.VendorNumber = k.VendorNumber
LEFT JOIN dim_product p ON p.Brand = k.Brand
LEFT JOIN dim_vendor  v ON v.VendorNumber = k.VendorNumber
LEFT JOIN vendor_total vt ON vt.VendorNumber = k.VendorNumber
LEFT JOIN mart_vendor_po vp ON vp.VendorNumber = k.VendorNumber;

CREATE INDEX ix_vendor_brand ON mart_vendor_brand(VendorNumber, Brand);

-- ---------- 1 dòng / NCC + cột Pareto (tỷ trọng doanh thu lũy kế) -----
DROP TABLE IF EXISTS mart_vendor;
CREATE TABLE mart_vendor AS
WITH agg AS (
    SELECT VendorNumber,
           MAX(VendorName)                 AS VendorName,
           COUNT(*)                        AS n_brands,
           SUM(has_purchase AND sales_qty = 0) AS n_unsold_brands,
           SUM(NOT has_purchase)           AS n_sales_only_brands,
           SUM(purchase_qty)               AS purchase_qty,
           SUM(purchase_dollars)           AS purchase_dollars,
           SUM(sales_qty)                  AS sales_qty,
           SUM(sales_dollars)              AS sales_dollars,
           SUM(excise)                     AS excise,
           SUM(gross_profit)               AS gross_profit
    FROM mart_vendor_brand
    GROUP BY VendorNumber
)
SELECT a.*,
       vp.n_po,
       COALESCE(vp.freight, 0)                                       AS freight,
       a.gross_profit - COALESCE(vp.freight, 0)                      AS net_profit_est,
       a.gross_profit / NULLIF(a.sales_dollars, 0) * 100             AS margin_pct,
       COALESCE(vp.freight, 0) / NULLIF(a.purchase_dollars, 0) * 100 AS freight_pct,
       a.sales_qty * 1.0 / NULLIF(a.purchase_qty, 0)                 AS stock_turnover,
       vp.avg_lead_days,
       vp.avg_pay_days,
       vp.approved_pct,
       a.sales_dollars / SUM(a.sales_dollars) OVER () * 100          AS sales_share_pct,
       a.purchase_dollars / SUM(a.purchase_dollars) OVER () * 100    AS purchase_share_pct,
       SUM(a.sales_dollars) OVER (ORDER BY a.sales_dollars DESC
                                  ROWS UNBOUNDED PRECEDING)
           / SUM(a.sales_dollars) OVER () * 100                      AS cum_sales_share_pct,
       ROW_NUMBER() OVER (ORDER BY a.sales_dollars DESC)             AS sales_rank
FROM agg a
LEFT JOIN mart_vendor_po vp USING (VendorNumber);

CREATE UNIQUE INDEX ux_mart_vendor ON mart_vendor(VendorNumber);
