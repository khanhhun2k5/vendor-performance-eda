# Thư mục `sql/`

Toàn bộ truy vấn SQL dùng cho 4 notebook EDA. Mục tiêu là chỉ quét dữ liệu lớn (`sales.csv`: 12,8 triệu dòng, 1,6 GB) **một lần duy nhất**, sau đó mọi notebook chỉ đọc các bảng tổng hợp nhỏ.

**Nguồn dữ liệu:** chỉ 6 file CSV trong `data/raw/`. **Không dùng `inventory.db`.** `vendor_sales_summary.csv` chỉ được nạp làm bảng tham chiếu `ref_vendor_sales_summary` và chỉ được dùng trong `build/07_validation.sql` để kiểm chứng.

```
data/raw/*.csv (6 file nguồn + vendor_sales_summary.csv tham chiếu)
      │  sql/staging/00_schema.sql + build_staging()      ← nạp 1 lần (~3–5 phút)
      ▼
data/interim/staging.db
      │  ATTACH … AS raw  (mode=ro)
      ▼
sql/build/01…08_*.sql  +  sql/templates/profile_*.sql      ← chạy 1 lần (~6–7 phút)
      │
      ▼
data/processed/analytics.db (~89 MB: dim_*, mart_*, sample_*, profile_columns, dq_checks)
      │
      ▼
sql/queries/*.sql  ── dl.query("<tên>", **tham_số) ──►  notebook 01–04 (mili-giây / truy vấn)
```

## `staging/`: nạp CSV

`00_schema.sql` khai báo kiểu cột giống file nguồn (BIGINT, FLOAT, TEXT) để SQLite tự ép chuỗi CSV sang số; ô rỗng được nạp thành NULL; khoảng trắng thừa được giữ nguyên như dữ liệu gốc.

## `build/`: dựng `analytics.db`

| File | Bảng tạo ra | Nội dung |
| --- | --- | --- |
| `01_dimensions.sql` | `dim_vendor`, `dim_product`, `dim_store` | Bảng chiều đã làm sạch: TRIM tên NCC, ép `Volume` sang số, điền City cho Store 46, phân khúc giá |
| `02_sales_marts.sql` | `mart_sales_daily`, `mart_sales_store_month`, `mart_sales_brand`, `mart_sales_vendor_month`, `sample_sales` | Tổng hợp `sales` theo ngày / cửa hàng × tháng / sản phẩm / NCC × tháng; mẫu hệ thống 1/50 |
| `03_purchase_marts.sql` | `map_invoice_po`, `mart_po`, `mart_purchases_daily`, `mart_purchases_store_month`, `mart_purchases_brand`, `mart_purchases_vendor_month`, `sample_purchases` | Tổng hợp `purchases`; ghép `vendor_invoice` theo (NCC, SL, tiền) vì số PO trên hóa đơn bị xáo trộn từ PO 12311 (lead time, thời gian thanh toán, phí vận chuyển, cờ lệch hóa đơn); mẫu 1/10 |
| `04_inventory_marts.sql` | `mart_inventory`, `mart_inventory_store` | FULL OUTER JOIN tồn đầu kỳ / cuối kỳ (qua bảng TEMP có index) |
| `05_vendor_marts.sql` | `mart_vendor_po`, `mart_vendor_brand`, `mart_vendor` | KPI NCC × sản phẩm (FULL JOIN mua ⟗ bán, phân bổ phí vận chuyển theo tiền mua), KPI NCC + cột Pareto |
| `06_quality_checks.sql` | `dq_checks` | Mỗi dòng là 1 vấn đề chất lượng dữ liệu kèm số dòng bị ảnh hưởng, đánh số theo mục §4 của `data/data_dictionary.md` |
| `07_validation.sql` | `vss_clean`, thêm dòng vào `dq_checks` | **Chỉ kiểm chứng:** so mart tự tính với `vendor_sales_summary.csv` (lệch giá trị + anti-join hai chiều) |
| `08_consistency_checks.sql` | `dq_dates`, `dq_calendar`, `mart_stock_flow`, `dq_consistency` | Kiểm tra ngày tháng (định dạng, phạm vi, ngày thiếu trong lịch 366 ngày), cân đối tồn kho từng `InventoryId`, 39 kiểm tra nhất quán giữa các file |

**Định nghĩa KPI dùng chung**

| KPI | Công thức |
| --- | --- |
| `lead_days` (PO) | ngày nhận **cuối** − `PODate` (nhận đủ hàng); kèm `lead_days_first` (nhận lô đầu) và `avg_line_lead_days` (trung bình theo dòng) |
| `pay_days` | `PayDate − InvoiceDate` |
| `gross_profit`, `margin_pct` | doanh thu − tiền mua; chia cho doanh thu × 100 (NULL nếu doanh thu = 0) |
| `stock_turnover` | SL bán / SL mua, tức tỷ lệ bán/mua (sell-through), không phải vòng quay kế toán |
| `freight_alloc` | phí vận chuyển của NCC × tỷ trọng tiền mua của sản phẩm trong NCC |
| `begin_value`, `end_value` | `onHand × Price` (giá **bán lẻ**, không phải giá vốn) |

`templates/profile_table.sql` và `templates/profile_column.sql` được `src/data_loader.py::build_profile` ghép lại để profiling mọi cột của một bảng trong **một lần quét**, rồi ghi vào `profile_columns`.

## `queries/`: truy vấn cho notebook

Dòng comment đầu mỗi file là mô tả của file đó (`dl.list_queries()` in ra danh sách này). Tham số dạng `:ten` được truyền qua `dl.query(name, ten=...)`; giá trị mặc định nằm ở `DEFAULT_PARAMS` trong `src/data_loader.py`.

| Notebook | Truy vấn |
| --- | --- |
| 01 Profiling | `mart_catalog`, `profile_tables`, `profile_columns(:table)`, `dq_checks`, `dq_dates`, `dq_calendar`, `dq_consistency(:severity)`, `invoice_match`, `invoice_shift`, `stock_flow_summary`, `vss_comparison` |
| 02 Distributions | `sample_sales`, `sample_purchases`, `products`, `po_metrics`, `vendor_brand(:min_purchase)`, `sales_daily`, `sales_weekday`, `sales_monthly`, `inventory_items`, `inventory_status` |
| 03 Relationships | `vendor_brand`, `vendor_kpi(:min_sales)`, `vendor_month_sales(:top_n)`, `price_band_summary`, `sales_vs_purchases_monthly`, `store_performance`, `store_month_sales`, `po_metrics` |
| 04 Exploration notes | `classification_summary`, `vendor_kpi`, `po_metrics`, `inventory_status`, `top_vendors(:top_n)`, `top_brands(:top_n)`, `slow_moving_brands(:max_turnover, :top_n)`, `promo_candidates(:sales_pct, :margin_pct)`, `vendor_brand`, `dq_checks` |

## Cách dùng

```python
from src import data_loader as dl
dl.build_marts()                    # lần đầu ~6–7 phút; các lần sau dùng lại ngay
dl.build_marts(force=True)          # dựng lại sau khi sửa file trong sql/build/
dl.query("top_vendors", top_n=15)   # chạy sql/queries/top_vendors.sql
dl.sql("SELECT * FROM mart_vendor WHERE margin_pct > 40")   # truy vấn tùy ý
```

## Thời gian build đo được

| Bước | Thời gian |
| --- | --- |
| Nạp CSV → `staging.db` | xem log `build_staging()` |
| `02_sales_marts.sql` | ~82 s |
| `03_purchase_marts.sql` | ~17 s |
| Các bước build còn lại | < 2 s mỗi bước |
| Profiling `sales` (COUNT DISTINCT trên 14 cột) | ~240 s |
| `08_consistency_checks.sql` | ~100 s |
| **Tổng phần build mart** | **~500 s** |

Đo trên máy hiện tại. Phần lớn thời gian nằm ở profiling, và bước này chỉ chạy lại khi gọi `force=True`.
