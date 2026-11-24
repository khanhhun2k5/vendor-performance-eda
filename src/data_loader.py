"""Nạp dữ liệu qua các file SQL trong thư mục ``sql/``.

Luồng làm việc
--------------
0. ``build_staging()`` nạp nguyên trạng các **CSV gốc** (``data/raw/*.csv``) vào
   ``data/interim/staging.db`` theo lược đồ ``sql/staging/00_schema.sql``.
   ``inventory.db`` KHÔNG được dùng; ``vendor_sales_summary.csv`` chỉ được nạp làm
   bảng tham chiếu ``ref_vendor_sales_summary`` để kiểm chứng.
1. ``build_marts()`` chạy *một lần* toàn bộ ``sql/build/*.sql`` trên staging
   (ATTACH chỉ đọc với tên ``raw``) và ghi kết quả vào ``data/processed/analytics.db``:
   các bảng ``dim_*``, ``mart_*``, ``sample_*``, ``profile_columns``, ``dq_checks``.
2. Notebook gọi ``query("<tên file trong sql/queries>", **tham_số)`` → chỉ đọc
   các bảng tổng hợp nhỏ nên mỗi truy vấn chạy trong mili-giây thay vì quét
   12,8 triệu dòng ``sales``.
"""
from __future__ import annotations

import csv
import re
import sqlite3
import time
from contextlib import closing
from datetime import datetime
from pathlib import Path
from typing import Any

import pandas as pd

from .config import (
    MART_DB,
    RAW_DIR,
    REFERENCE_CSV,
    SOURCE_TABLES,
    SQL_BUILD_DIR,
    SQL_STAGING_DIR,
    STAGING_DB,
    SQL_QUERY_DIR,
    SQL_TEMPLATE_DIR,
)

# Tham số mặc định cho các truy vấn có tham số (:top_n, :min_sales, ...).
DEFAULT_PARAMS: dict[str, Any] = {
    "table": "*",
    "top_n": 10,
    "min_sales": 0,
    "min_purchase": 0,
    "max_turnover": 0.5,
    "sales_pct": 0.25,
    "margin_pct": 0.75,
    "severity": "*",
}

_QUERY_CACHE: dict[tuple, pd.DataFrame] = {}


def _log(msg: str) -> None:
    """print an toàn với console Windows (cp1252) khi chuỗi có dấu tiếng Việt."""
    try:
        print(msg, flush=True)
    except UnicodeEncodeError:
        print(msg.encode("ascii", "backslashreplace").decode("ascii"), flush=True)


# --------------------------------------------------------------------------- #
# Kết nối
# --------------------------------------------------------------------------- #
def _ro_uri(path: Path) -> str:
    """URI chỉ đọc (an toàn với đường dẫn có dấu tiếng Việt / khoảng trắng)."""
    return path.resolve().as_uri() + "?mode=ro"


def connect_staging() -> sqlite3.Connection:
    """Kết nối chỉ đọc tới ``staging.db`` (CSV gốc đã nạp; tự nạp nếu chưa có)."""
    if not STAGING_DB.exists():
        build_staging()
    return sqlite3.connect(_ro_uri(STAGING_DB), uri=True)


def connect_mart() -> sqlite3.Connection:
    """Kết nối chỉ đọc tới ``analytics.db`` (tự build nếu chưa có)."""
    if not MART_DB.exists():
        build_marts()
    return sqlite3.connect(_ro_uri(MART_DB), uri=True)


# --------------------------------------------------------------------------- #
# Nạp CSV gốc → staging.db
# --------------------------------------------------------------------------- #
def _read_sql_file(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _float_or_none(v: str):
    """Ép chuỗi sang float (hiểu cả 'inf'/'-inf'); rỗng → None."""
    if v == "":
        return None
    try:
        return float(v)
    except ValueError:
        return v


def _load_csv(conn: sqlite3.Connection, table: str, csv_path: Path,
              strict_float: bool = False, batch: int = 200_000) -> int:
    """Nạp 1 file CSV vào bảng đã tạo sẵn; ô rỗng → NULL.

    Giá trị được chèn dạng chuỗi, SQLite tự ép sang INTEGER/REAL theo kiểu khai
    báo của cột (giữ nguyên khoảng trắng thừa như dữ liệu gốc). ``strict_float``
    dùng cho bảng có 'inf'/'-inf' (SQLite không tự hiểu các chuỗi này).
    """
    n_cols = len(conn.execute(f'PRAGMA table_info("{table}")').fetchall())
    sql = f'INSERT INTO "{table}" VALUES ({",".join("?" * n_cols)})'
    conv = _float_or_none if strict_float else (lambda v: None if v == "" else v)
    n = 0
    with open(csv_path, newline="", encoding="utf-8") as fh:
        reader = csv.reader(fh)
        header = next(reader)
        if len(header) != n_cols:
            raise ValueError(f"{csv_path.name}: {len(header)} cột, lược đồ có {n_cols} cột")
        buf = []
        for row in reader:
            buf.append([conv(v) for v in row])
            if len(buf) >= batch:
                conn.executemany(sql, buf)
                n += len(buf)
                buf.clear()
        if buf:
            conn.executemany(sql, buf)
            n += len(buf)
    return n


def build_staging(force: bool = False, verbose: bool = True) -> Path:
    """Nạp 6 CSV nguồn + CSV tham chiếu vào ``data/interim/staging.db`` (~3–5 phút)."""
    if STAGING_DB.exists() and not force:
        if verbose:
            _log(f"staging.db đã có ({STAGING_DB.stat().st_size / 1e6:.0f} MB) — dùng lại.")
        return STAGING_DB
    STAGING_DB.parent.mkdir(parents=True, exist_ok=True)
    tmp = STAGING_DB.with_suffix(".building.db")
    tmp.unlink(missing_ok=True)
    t_all = time.perf_counter()
    with closing(sqlite3.connect(tmp)) as conn:
        conn.executescript("PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;")
        conn.executescript(_read_sql_file(SQL_STAGING_DIR / "00_schema.sql"))
        jobs = [(t, RAW_DIR / f"{t}.csv", False) for t in SOURCE_TABLES]
        jobs += [(t, RAW_DIR / f, True) for t, f in REFERENCE_CSV.items()]
        for table, path, strict in jobs:
            t0 = time.perf_counter()
            n = _load_csv(conn, table, path, strict_float=strict)
            conn.commit()
            if verbose:
                _log(f"  nạp {path.name:<28} {n:>12,} dòng  {time.perf_counter() - t0:6.1f} s")
    tmp.replace(STAGING_DB)
    if verbose:
        _log(f"Xong staging.db ({STAGING_DB.stat().st_size / 1e6:.0f} MB) "
             f"trong {time.perf_counter() - t_all:.0f} s")
    return STAGING_DB


# --------------------------------------------------------------------------- #
# Build analytics.db
# --------------------------------------------------------------------------- #


def _strip_header_comments(sql: str) -> str:
    """Bỏ các dòng comment ``--`` để ghép template an toàn."""
    return "\n".join(ln for ln in sql.splitlines() if not ln.strip().startswith("--")).strip()


def build_profile(conn: sqlite3.Connection, verbose: bool = True) -> pd.DataFrame:
    """Profiling 6 bảng nguồn (CSV) (null, distinct, zero, min/max, mean) → ``profile_columns``.

    Mỗi bảng chỉ quét 1 lần nhờ ghép mọi cột vào 1 câu SELECT từ template
    ``sql/templates/profile_table.sql`` + ``profile_column.sql``.
    """
    table_tpl = _strip_header_comments(_read_sql_file(SQL_TEMPLATE_DIR / "profile_table.sql"))
    col_tpl = _strip_header_comments(_read_sql_file(SQL_TEMPLATE_DIR / "profile_column.sql"))

    records = []
    for table in SOURCE_TABLES:
        t0 = time.perf_counter()
        cols = conn.execute(f'PRAGMA raw.table_info("{table}")').fetchall()  # (cid, name, type, ...)
        exprs = ",\n".join(col_tpl.format(col=c[1], i=c[0]) for c in cols)
        cur = conn.execute(table_tpl.format(table=table, column_exprs=exprs))
        res = dict(zip([d[0] for d in cur.description], cur.fetchone()))
        n_rows = res["n_rows"]
        for cid, cname, ctype, *_ in cols:
            p = f"c{cid}_"
            records.append({
                "table_name": table, "ordinal": cid, "column_name": cname,
                "declared_type": ctype, "n_rows": n_rows,
                "n_null": res[p + "n_null"], "n_distinct": res[p + "n_distinct"],
                "n_zero": res[p + "n_zero"], "n_untrimmed": res[p + "n_untrimmed"],
                "min_value": None if res[p + "min"] is None else str(res[p + "min"]),
                "max_value": None if res[p + "max"] is None else str(res[p + "max"]),
                "mean_value": res[p + "mean"],
            })
        if verbose:
            _log(f"  profile {table:<22} {n_rows:>12,} dòng  {time.perf_counter() - t0:6.1f} s")

    prof = pd.DataFrame.from_records(records)
    prof["null_pct"] = prof["n_null"] / prof["n_rows"] * 100
    prof["distinct_pct"] = prof["n_distinct"] / prof["n_rows"] * 100
    prof.to_sql("profile_columns", conn, if_exists="replace", index=False)
    return prof


def build_marts(force: bool = False, verbose: bool = True) -> Path:
    """Chạy ``sql/build/*.sql`` (theo thứ tự tên file) + profiling → ``analytics.db``.

    Nguồn là ``staging.db`` (CSV gốc), tự nạp nếu chưa có.

    Ghi vào file tạm rồi đổi tên ⇒ không bao giờ để lại analytics.db dở dang.
    ``force=True`` để dựng lại (vd khi sửa file SQL build).
    """
    if MART_DB.exists() and not force:
        if verbose:
            _log(f"analytics.db đã có ({MART_DB.stat().st_size / 1e6:.1f} MB) — dùng lại. "
                  "Gọi build_marts(force=True) để dựng lại.")
        return MART_DB

    build_staging(verbose=verbose)
    MART_DB.parent.mkdir(parents=True, exist_ok=True)
    tmp = MART_DB.with_suffix(".building.db")
    tmp.unlink(missing_ok=True)
    t_all = time.perf_counter()

    # uri=True để lệnh ATTACH hiểu URI "?mode=ro" của staging.db.
    with closing(sqlite3.connect(tmp.resolve().as_uri(), uri=True)) as conn:
        conn.executescript(
            "PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;"
            "PRAGMA temp_store = MEMORY; PRAGMA cache_size = -524288;"  # ~512 MB cache
        )
        conn.execute("ATTACH DATABASE ? AS raw", (_ro_uri(STAGING_DB),))
        for f in sorted(SQL_BUILD_DIR.glob("*.sql")):
            t0 = time.perf_counter()
            conn.executescript(_read_sql_file(f))
            if verbose:
                _log(f"  {f.name:<28} {time.perf_counter() - t0:6.1f} s")
        build_profile(conn, verbose=verbose)
        conn.execute("DROP TABLE IF EXISTS build_info")
        conn.execute("CREATE TABLE build_info (built_at TEXT, seconds REAL, source TEXT)")
        conn.execute("INSERT INTO build_info VALUES (?, ?, ?)",
                     (datetime.now().isoformat(timespec="seconds"),
                      time.perf_counter() - t_all, f"CSV trong {RAW_DIR} (qua {STAGING_DB.name})"))
        conn.commit()
        conn.execute("DETACH DATABASE raw")
        conn.execute("VACUUM")

    tmp.replace(MART_DB)
    _QUERY_CACHE.clear()
    if verbose:
        _log(f"Xong: {MART_DB} ({MART_DB.stat().st_size / 1e6:.1f} MB) "
              f"trong {time.perf_counter() - t_all:.0f} s")
    return MART_DB


# --------------------------------------------------------------------------- #
# Truy vấn
# --------------------------------------------------------------------------- #
def list_queries() -> pd.DataFrame:
    """Danh sách file trong ``sql/queries`` kèm dòng mô tả đầu tiên."""
    rows = []
    for f in sorted(SQL_QUERY_DIR.glob("*.sql")):
        first = next((ln for ln in _read_sql_file(f).splitlines() if ln.startswith("--")), "")
        rows.append({"query": f.stem, "mô tả": first.lstrip("- ").strip()})
    return pd.DataFrame(rows)


_NAME_RE = re.compile(r"^\w+$")


def _check_name(name: str) -> str:
    """Chỉ chấp nhận tên dạng chữ/số/gạch dưới (chặn '../' và chèn SQL qua tên bảng)."""
    if not _NAME_RE.match(name):
        raise ValueError(f"Tên không hợp lệ: {name!r}")
    return name


def load_sql(name: str) -> str:
    """Đọc nội dung ``sql/queries/<name>.sql``."""
    path = SQL_QUERY_DIR / f"{_check_name(name.removesuffix('.sql'))}.sql"
    if not path.exists():
        raise FileNotFoundError(f"Không có truy vấn '{name}'. Xem list_queries().")
    return _read_sql_file(path)


def query(name: str, use_cache: bool = True, **params: Any) -> pd.DataFrame:
    """Chạy truy vấn có tên trong ``sql/queries`` trên ``analytics.db``.

    Ví dụ: ``query("top_vendors", top_n=15)``. Tham số không truyền lấy từ
    ``DEFAULT_PARAMS``. Kết quả được cache trong phiên (trả về bản sao).
    """
    text = load_sql(name)
    used = set(re.findall(r":(\w+)", text))
    unknown = set(params) - used
    if unknown:
        raise TypeError(f"Truy vấn '{name}' không có tham số {sorted(unknown)}; "
                        f"tham số hợp lệ: {sorted(used)}")
    merged = {k: v for k, v in {**DEFAULT_PARAMS, **params}.items() if k in used}
    # Khóa cache gồm cả nội dung SQL ⇒ sửa file .sql trong phiên vẫn lấy kết quả mới
    key = (name, hash(text), tuple(sorted(merged.items())))
    if use_cache and key in _QUERY_CACHE:
        return _QUERY_CACHE[key].copy()
    with closing(connect_mart()) as conn:
        df = pd.read_sql_query(text, conn, params=merged)
    _QUERY_CACHE[key] = df
    return df.copy()


def sql(text: str, **params: Any) -> pd.DataFrame:
    """Chạy câu SQL tùy ý (ad-hoc) trên ``analytics.db``."""
    with closing(connect_mart()) as conn:
        return pd.read_sql_query(text, conn, params=params or None)


def read_table(name: str) -> pd.DataFrame:
    """Đọc nguyên 1 bảng trong ``analytics.db`` (vd ``mart_vendor``)."""
    return sql(f'SELECT * FROM "{_check_name(name)}"')


def mart_catalog() -> pd.DataFrame:
    """Danh sách bảng trong analytics.db kèm số dòng."""
    tables = query("mart_catalog", use_cache=False)
    with closing(connect_mart()) as conn:
        tables["n_rows"] = [conn.execute(f'SELECT COUNT(*) FROM "{_check_name(t)}"').fetchone()[0]
                            for t in tables["table_name"]]
    return tables
