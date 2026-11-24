"""Đường dẫn dùng chung cho toàn dự án (tính từ thư mục gốc repo).

Nguồn dữ liệu là **các file CSV gốc** trong ``data/raw/``.
``data/raw/inventory.db`` KHÔNG được dùng. ``vendor_sales_summary.csv`` chỉ được
nạp làm bảng tham chiếu để kiểm chứng kết quả tự tính.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

DATA_DIR = ROOT / "data"
RAW_DIR = DATA_DIR / "raw"                              # CSV gốc (chỉ đọc)
STAGING_DB = DATA_DIR / "interim" / "staging.db"        # CSV nạp nguyên trạng vào SQLite
MART_DB = DATA_DIR / "processed" / "analytics.db"       # bảng tổng hợp do sql/build/*.sql tạo ra

SQL_DIR = ROOT / "sql"
SQL_STAGING_DIR = SQL_DIR / "staging"
SQL_BUILD_DIR = SQL_DIR / "build"
SQL_QUERY_DIR = SQL_DIR / "queries"
SQL_TEMPLATE_DIR = SQL_DIR / "templates"

REPORT_DIR = ROOT / "reports"
FIGURE_DIR = REPORT_DIR / "figure"
TABLE_DIR = REPORT_DIR / "table"

# 6 bảng nguồn dùng để phân tích: tên bảng staging = tên file CSV
SOURCE_TABLES = (
    "begin_inventory",
    "end_inventory",
    "purchase_prices",
    "purchases",
    "sales",
    "vendor_invoice",
)
# Bảng tham chiếu, chỉ dùng trong sql/build/07_validation.sql
REFERENCE_CSV = {"ref_vendor_sales_summary": "vendor_sales_summary.csv"}
