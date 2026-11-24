# Kho dữ liệu: Vendor Performance Analysis (EDA)

Phân tích khám phá bộ dữ liệu bán lẻ rượu năm 2024 (Kaggle *Vendor Performance Analysis*). Mô tả từng cột xem tại [data/data_dictionary.md](data/data_dictionary.md). Tóm tắt kết quả xem tại [reports/eda_findings.md](reports/eda_findings.md).

## Cấu trúc

| Thư mục | Nội dung |
| --- | --- |
| `data/raw/` | **6 CSV nguồn** + `vendor_sales_summary.csv` (chỉ để kiểm chứng). `inventory.db` **không được dùng** |
| `data/interim/staging.db` | CSV nạp nguyên trạng vào SQLite (`sql/staging`) |
| `data/processed/analytics.db` | Bảng tổng hợp do `sql/build` sinh ra (~89 MB) |
| `sql/` | `staging/` nạp CSV, `build/` dựng mart và kiểm chứng, `queries/` chứa truy vấn cho notebook, `templates/` chứa mẫu profiling. Xem [sql/README.md](sql/README.md) |
| `src/` | `config` (đường dẫn), `data_loader` (build + chạy SQL), `preprocessing` (thống kê, Pareto, định dạng), `visualization` (biểu đồ xuất bản, bảng màu đậm) |
| `notebook/` | `01-data-profiling`, `02-distributions`, `03-relationships`, `04-exploration-notes` |
| `reports/figure/` | Biểu đồ PNG 300 dpi + PDF |
| `reports/table/` | Bảng CSV xuất từ notebook |
| `reports/eda_findings.md` | Báo cáo tổng hợp phát hiện EDA và chất lượng dữ liệu |
| `tests/` | 21 test pytest: hàm thống kê và test tích hợp toàn bộ pipeline SQL trên CSV tổng hợp |

## Dữ liệu

Repo **không chứa dữ liệu** (khoảng 1,9 GB CSV). Tải bộ [Vendor Performance Analysis](https://www.kaggle.com/datasets/harshmadhavan/vendor-performance-analysis) trên Kaggle, rồi đặt 7 file CSV vào `data/raw/`:

```text
data/raw/begin_inventory.csv   end_inventory.csv   purchase_prices.csv
         purchases.csv         sales.csv           vendor_invoice.csv
         vendor_sales_summary.csv      # chỉ dùng để kiểm chứng
```

`staging.db` và `analytics.db` được sinh tự động từ các CSV này.

## Chạy

```bash
pip install -r requirements.txt
# Lần đầu: nạp CSV → staging.db rồi dựng analytics.db (~10 phút). Notebook 01 cũng tự gọi bước này.
python -c "from src.data_loader import build_marts; build_marts()"
python -m pytest tests -q          # kiểm tra src/ + pipeline SQL (~3 s)
# Chạy toàn bộ notebook (mỗi notebook ~20–55 s, phần lớn là thời gian lưu hình)
cd notebook
for f in 0*.ipynb; do python -m nbconvert --to notebook --execute --inplace "$f"; done
```

Chạy notebook theo thứ tự 01 → 04. Notebook 01 dựng `analytics.db` nếu file này chưa có.
