"""Tiền xử lý & thống kê mô tả dùng chung cho các notebook EDA.

Phần làm sạch nặng (strip tên NCC, ép kiểu Volume, điền City, −inf → NULL) đã làm
trong ``sql/build``. Module này chỉ làm phần nhẹ trên DataFrame đã tổng hợp.
"""
from __future__ import annotations

from collections.abc import Iterable, Sequence

import numpy as np
import pandas as pd

CLASS_NAMES = {1: "Rượu mạnh", 2: "Rượu vang"}
WEEKDAY_VI = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]          # strftime('%w'): 0 = Chủ nhật
MONTH_VI = [f"Th{m}" for m in range(1, 13)]


# --------------------------------------------------------------------------- #
# Kiểu dữ liệu
# --------------------------------------------------------------------------- #
def parse_dates(df: pd.DataFrame, cols: Iterable[str], fmt: str = "%Y-%m-%d") -> pd.DataFrame:
    """Ép các cột ngày dạng chuỗi ISO sang ``datetime64`` (lỗi → NaT)."""
    out = df.copy()
    for c in cols:
        if c in out:
            out[c] = pd.to_datetime(out[c], format=fmt, errors="coerce")
    return out


def add_class_name(df: pd.DataFrame, col: str = "Classification",
                   new_col: str = "ClassName") -> pd.DataFrame:
    """Thêm cột tên nhóm sản phẩm (1 = Rượu mạnh, 2 = Rượu vang)."""
    out = df.copy()
    out[new_col] = out[col].map(CLASS_NAMES).astype("category")
    return out


def month_label(month: pd.Series) -> pd.Series:
    """'2024-03' → 'Th3'."""
    return month.str[-2:].astype(int).map(lambda m: MONTH_VI[m - 1])


def replace_inf(df: pd.DataFrame) -> pd.DataFrame:
    """Thay ±inf bằng NaN ở mọi cột số."""
    return df.replace([np.inf, -np.inf], np.nan)


# --------------------------------------------------------------------------- #
# Thống kê mô tả & ngoại lai
# --------------------------------------------------------------------------- #
def describe_distribution(df: pd.DataFrame, cols: Sequence[str]) -> pd.DataFrame:
    """Bảng mô tả mở rộng: phân vị 1/5/25/50/75/95/99 %, skew, kurtosis, % = 0."""
    rows = {}
    for c in cols:
        s = pd.to_numeric(df[c], errors="coerce").dropna()
        q = s.quantile([0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99])
        rows[c] = {
            "n": s.size, "mean": s.mean(), "std": s.std(), "min": s.min(),
            "p1": q[0.01], "p5": q[0.05], "p25": q[0.25], "median": q[0.5],
            "p75": q[0.75], "p95": q[0.95], "p99": q[0.99], "max": s.max(),
            "skew": s.skew(), "kurtosis": s.kurt(), "zero_pct": (s == 0).mean() * 100,
        }
    return pd.DataFrame(rows).T


def iqr_bounds(s: pd.Series, k: float = 1.5) -> tuple[float, float]:
    """Ngưỡng ngoại lai Tukey: [Q1 − k·IQR, Q3 + k·IQR]."""
    q1, q3 = s.quantile([0.25, 0.75])
    iqr = q3 - q1
    return q1 - k * iqr, q3 + k * iqr


def outlier_summary(df: pd.DataFrame, cols: Sequence[str], k: float = 1.5,
                    log: bool = False) -> pd.DataFrame:
    """Đếm ngoại lai theo IQR cho từng cột (tùy chọn trên thang log10 với giá trị > 0)."""
    rows = {}
    for c in cols:
        s = pd.to_numeric(df[c], errors="coerce").dropna()
        if log:
            s = np.log10(s[s > 0])
        lo, hi = iqr_bounds(s, k)
        rows[c] = {
            "n": s.size, "lower": 10 ** lo if log else lo, "upper": 10 ** hi if log else hi,
            "n_low": int((s < lo).sum()), "n_high": int((s > hi).sum()),
            "outlier_pct": float(((s < lo) | (s > hi)).mean() * 100),
        }
    return pd.DataFrame(rows).T


def positive(s: pd.Series) -> pd.Series:
    """Giữ giá trị > 0 (dùng trước khi vẽ thang log)."""
    s = pd.to_numeric(s, errors="coerce")
    return s[s > 0]


# --------------------------------------------------------------------------- #
# Chỉ số tập trung / Pareto
# --------------------------------------------------------------------------- #
def n_to_reach_share(cum_share_pct: pd.Series, threshold: float = 80.0) -> int:
    """Số phần tử (đã xếp giảm dần) cần để tỷ trọng lũy kế đạt ``threshold`` %."""
    cum = cum_share_pct.dropna().to_numpy()
    return int(min((cum < threshold).sum() + 1, len(cum)))


def gini(values: Sequence[float]) -> float:
    """Hệ số Gini (0 = đều tuyệt đối, 1 = tập trung tuyệt đối)."""
    x = np.sort(np.asarray(values, dtype=float))
    x = x[x >= 0]
    if x.size == 0 or x.sum() == 0:
        return float("nan")
    n = x.size
    return float((2 * np.arange(1, n + 1) - n - 1).dot(x) / (n * x.sum()))


def hhi(shares_pct: Sequence[float]) -> float:
    """Chỉ số Herfindahl–Hirschman từ tỷ trọng % (0–10 000)."""
    s = np.asarray(shares_pct, dtype=float)
    return float(np.nansum(s ** 2))


# --------------------------------------------------------------------------- #
# Định dạng
# --------------------------------------------------------------------------- #
def fmt_money(x: float) -> str:
    """1234567 → '$1.23M' (K = nghìn, M = triệu, B = tỷ); số âm → '-$…'."""
    if pd.isna(x):
        return "—"
    sign, a = ("-" if x < 0 else ""), abs(x)
    if a >= 1e9:
        return f"{sign}${a / 1e9:.2f}B"
    if a >= 1e6:
        return f"{sign}${a / 1e6:.2f}M"
    if a >= 1e3:
        return f"{sign}${a / 1e3:.1f}K"
    return f"{sign}${a:.2f}"


def style_table(df: pd.DataFrame, money: Sequence[str] = (), pct: Sequence[str] = (),
                num: Sequence[str] = (), dec: Sequence[str] = ()):
    """Định dạng hiển thị DataFrame trong notebook (không đổi dữ liệu)."""
    fmt = {c: "${:,.0f}" for c in money}
    fmt.update({c: "{:.1f}%" for c in pct})
    fmt.update({c: "{:,.0f}" for c in num})
    fmt.update({c: "{:,.2f}" for c in dec})
    return df.style.format(fmt, na_rep="—").hide(axis="index")
