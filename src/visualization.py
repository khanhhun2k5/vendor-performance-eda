"""Biểu đồ phong cách xuất bản (theo skill *scientific-figure-making*), bảng màu ĐẬM.

Quy ước
-------
* Bỏ viền trên/phải, legend không khung, font sans-serif hỗ trợ tiếng Việt.
* Bảng màu là bản **đậm hơn** của palette chuẩn (blue #0F4D92 → #0A3A75, …);
  không dùng các tông pastel nhạt để biểu đồ rõ khi in / chiếu.
* Cột có viền đen, đường dày 2.4; xuất PNG 300 dpi + PDF vào ``reports/figure``.
"""
from __future__ import annotations

from collections.abc import Mapping, Sequence
from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.ticker import FuncFormatter, PercentFormatter

from .config import FIGURE_DIR

# --------------------------------------------------------------------------- #
# Bảng màu đậm
# --------------------------------------------------------------------------- #
PALETTE: dict[str, str] = {
    "blue": "#0A3A75",        # màu chủ đạo (đậm hơn #0F4D92)
    "blue_2": "#1F5C9E",
    "wine": "#8C1C2E",        # đỏ rượu vang (đậm hơn #B64342)
    "red": "#A11D21",
    "green": "#1E6B34",       # (đậm hơn #8BCF8B)
    "teal": "#0E5E66",
    "violet": "#5E2160",
    "orange": "#B5530A",
    "gold": "#A67C00",
    "gray": "#4A4A4A",
    "dark": "#1A1A1A",
    "light_gray": "#9A9A9A",
}
SEQ_COLORS = [PALETTE[k] for k in ("blue", "wine", "green", "orange", "violet", "teal", "gold", "gray")]
CLASS_COLORS = {1: PALETTE["blue"], 2: PALETTE["wine"],
                "Rượu mạnh": PALETTE["blue"], "Rượu vang": PALETTE["wine"]}

# Thang màu tuần tự (trắng xanh nhạt → xanh navy rất đậm) và phân kỳ (đỏ ↔ xanh)
CMAP_SEQ = LinearSegmentedColormap.from_list("seq_dark", ["#DCE6F2", "#5B86B8", "#0A3A75", "#041C3D"])
CMAP_DIV = LinearSegmentedColormap.from_list("div_dark", ["#7A1020", "#C45A62", "#F4F1EE", "#4F7DB3", "#0A3A75"])


def set_style(font_size: int = 13, axes_linewidth: float = 1.8) -> None:
    """Cấu hình rcParams một lần ở đầu notebook."""
    mpl.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
        "font.size": font_size,
        "axes.titlesize": font_size + 1,
        "axes.titleweight": "bold",
        "axes.labelsize": font_size,
        "axes.labelcolor": PALETTE["dark"],
        "axes.edgecolor": PALETTE["dark"],
        "axes.linewidth": axes_linewidth,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.prop_cycle": mpl.cycler(color=SEQ_COLORS),
        "xtick.color": PALETTE["dark"],
        "ytick.color": PALETTE["dark"],
        "xtick.major.width": axes_linewidth,
        "ytick.major.width": axes_linewidth,
        "legend.frameon": False,
        "legend.fontsize": font_size - 1,
        "lines.linewidth": 2.4,
        "patch.edgecolor": "black",
        "figure.dpi": 110,
        "savefig.dpi": 300,
        "savefig.bbox": "tight",
        "savefig.facecolor": "white",
        "svg.fonttype": "none",
        "pdf.fonttype": 42,
    })


# --------------------------------------------------------------------------- #
# Khung hình & lưu file
# --------------------------------------------------------------------------- #
def new_figure(nrows: int = 1, ncols: int = 1, figsize: tuple[float, float] | None = None,
               **kwargs):
    """Trả về ``(fig, axes)``; ``axes`` luôn là mảng 1 chiều (kể cả 1 ô)."""
    figsize = figsize or (6.4 * ncols, 4.4 * nrows)
    fig, axes = plt.subplots(nrows, ncols, figsize=figsize, squeeze=False, **kwargs)
    return fig, axes.ravel()


def save_figure(fig, name: str, formats: Sequence[str] = ("png", "pdf"),
                out_dir: Path = FIGURE_DIR, pad: float = 1.0) -> list[Path]:
    """``tight_layout`` rồi lưu ``reports/figure/<name>.<ext>``."""
    out_dir.mkdir(parents=True, exist_ok=True)
    fig.tight_layout(pad=pad)
    paths = []
    for ext in formats:
        p = out_dir / f"{name}.{ext}"
        fig.savefig(p)
        paths.append(p)
    return paths


# --------------------------------------------------------------------------- #
# Định dạng trục
# --------------------------------------------------------------------------- #
def _short(x: float, prefix: str = "") -> str:
    a = abs(x)
    for div, suf in ((1e9, "B"), (1e6, "M"), (1e3, "K")):
        if a >= div:
            v = x / div
            return f"{prefix}{v:.0f}{suf}" if v == int(v) else f"{prefix}{v:.1f}{suf}"
    return f"{prefix}{x:.0f}" if x == int(x) else f"{prefix}{x:.2g}"


# "\$" = ký hiệu $ đã escape (mathtext bật để nhãn trục log 10^n hiển thị đúng)
money_fmt = FuncFormatter(lambda x, _: ("−" if x < 0 else "") + _short(abs(x), r"\$"))
count_fmt = FuncFormatter(lambda x, _: _short(x))


def fmt_axis(ax, x: str | None = None, y: str | None = None) -> None:
    """Gán formatter: 'money' | 'count' | 'pct' cho trục x / y."""
    table = {"money": money_fmt, "count": count_fmt, "pct": PercentFormatter(decimals=0)}
    if x:
        ax.xaxis.set_major_formatter(table[x])
    if y:
        ax.yaxis.set_major_formatter(table[y])


def label(ax, title: str | None = None, xlabel: str | None = None,
          ylabel: str | None = None) -> None:
    if title:
        ax.set_title(title, loc="left")
    if xlabel is not None:
        ax.set_xlabel(xlabel)
    if ylabel is not None:
        ax.set_ylabel(ylabel)


# --------------------------------------------------------------------------- #
# Các loại biểu đồ
# --------------------------------------------------------------------------- #
def hist(ax, data: pd.Series | Mapping[str, pd.Series], bins: int = 60, log_x: bool = False,
         colors: Sequence[str] | None = None, density: bool = False, show_median: bool = True,
         alpha: float = 0.85, log_y: bool = False, color: str | None = None):
    """Histogram 1 hoặc nhiều nhóm (dict tên → Series). ``log_x`` chia bin đều trên log10."""
    groups = data if isinstance(data, Mapping) else {None: data}
    colors = colors or ([color] if color else SEQ_COLORS)
    allv = pd.concat([pd.Series(v, dtype=float) for v in groups.values()]).dropna()
    if log_x:
        allv = allv[allv > 0]
        edges = np.logspace(np.log10(allv.min()), np.log10(allv.max()), bins + 1)
    else:
        edges = np.linspace(allv.min(), allv.max(), bins + 1)
    for (name, v), c in zip(groups.items(), colors):
        v = pd.Series(v, dtype=float).dropna()
        if log_x:
            v = v[v > 0]
        ax.hist(v, bins=edges, color=c, alpha=alpha if len(groups) > 1 else 0.95,
                edgecolor="black", linewidth=0.5, density=density, label=name,
                histtype="stepfilled" if len(groups) > 1 else "bar")
        if show_median:
            ax.axvline(v.median(), color=c if len(groups) > 1 else PALETTE["wine"],
                       ls="--", lw=2, label=f"Trung vị{'' if name is None else ' ' + name}: {v.median():,.4g}")
    if log_x:
        ax.set_xscale("log")
    if log_y:
        ax.set_yscale("log")
    ax.legend()
    return ax


def barh(ax, labels: Sequence[str], values: Sequence[float], color: str | Sequence[str] = PALETTE["blue"],
         annotate: str | None = "{:,.0f}", fontsize: int = 10, invert: bool = True):
    """Thanh ngang (xếp hạng). ``annotate`` là format chuỗi hoặc None."""
    y = np.arange(len(labels))
    bars = ax.barh(y, values, color=color, edgecolor="black", linewidth=1.0)
    ax.set_yticks(y, labels)
    if invert:
        ax.invert_yaxis()
    if annotate:
        ax.bar_label(bars, labels=[annotate.format(v) for v in values], padding=3,
                     fontsize=fontsize, color=PALETTE["dark"])
        ax.margins(x=0.15)
    return bars


def bar(ax, labels: Sequence[str], series: Mapping[str, Sequence[float]],
        colors: Sequence[str] | None = None, annotate: str | None = None,
        fontsize: int = 9, width: float = 0.8):
    """Cột nhóm: ``series`` = {tên nhóm: giá trị theo labels}."""
    colors = colors or SEQ_COLORS
    k = len(series)
    x = np.arange(len(labels))
    w = width / k
    out = []
    for i, ((name, vals), c) in enumerate(zip(series.items(), colors)):
        b = ax.bar(x + (i - (k - 1) / 2) * w, vals, w, label=name, color=c,
                   edgecolor="black", linewidth=1.0)
        if annotate:
            ax.bar_label(b, labels=[annotate.format(v) for v in vals], padding=2, fontsize=fontsize)
        out.append(b)
    ax.set_xticks(x, labels)
    if k > 1:
        ax.legend()
    return out


def lines(ax, x: Sequence, series: Mapping[str, Sequence[float]], colors: Sequence[str] | None = None,
          markers: bool = True, band: Mapping[str, tuple[Sequence[float], Sequence[float]]] | None = None):
    """Nhiều đường xu hướng; ``band`` = {tên: (cận dưới, cận trên)} để tô vùng."""
    colors = colors or SEQ_COLORS
    for (name, y), c in zip(series.items(), colors):
        ax.plot(x, y, color=c, marker="o" if markers else None, ms=5, label=name)
        if band and name in band:
            lo, hi = band[name]
            ax.fill_between(x, lo, hi, color=c, alpha=0.18, lw=0)
    if len(series) > 1:
        ax.legend()
    return ax


def heatmap(ax, matrix: pd.DataFrame, cmap=CMAP_SEQ, annotate: bool = False, fmt: str = "{:.2f}",
            cbar_label: str | None = None, center: float | None = None, vmin=None, vmax=None,
            fontsize: int = 9):
    """Heatmap từ DataFrame (index → hàng, columns → cột)."""
    data = matrix.to_numpy(dtype=float)
    if center is not None:
        span = np.nanmax(np.abs(data - center))
        vmin, vmax = center - span, center + span
    im = ax.imshow(data, cmap=cmap, aspect="auto", vmin=vmin, vmax=vmax)
    ax.set_xticks(range(matrix.shape[1]), matrix.columns, rotation=45, ha="right")
    ax.set_yticks(range(matrix.shape[0]), matrix.index)
    for s in ax.spines.values():
        s.set_visible(False)
    cb = ax.figure.colorbar(im, ax=ax, fraction=0.046, pad=0.03)
    cb.outline.set_linewidth(1)
    if cbar_label:
        cb.set_label(cbar_label)
    if annotate:
        lo, hi = im.get_clim()
        for i in range(data.shape[0]):
            for j in range(data.shape[1]):
                v = data[i, j]
                if np.isnan(v):
                    continue
                rel = (v - lo) / (hi - lo + 1e-12)
                dark_bg = rel > 0.55 if center is None else abs(rel - 0.5) > 0.3
                ax.text(j, i, fmt.format(v), ha="center", va="center", fontsize=fontsize,
                        color="white" if dark_bg else PALETTE["dark"], fontweight="bold")
    return im


def scatter(ax, x, y, color: str = PALETTE["blue"], size: float = 18, alpha: float = 0.6,
            label: str | None = None, log_x: bool = False, log_y: bool = False, c=None, cmap=CMAP_SEQ):
    """Scatter (viền đen mảnh để điểm nổi rõ trên nền trắng)."""
    sc = ax.scatter(x, y, s=size, alpha=alpha, color=None if c is not None else color, c=c,
                    cmap=cmap if c is not None else None, edgecolor="black", linewidth=0.3, label=label)
    if log_x:
        ax.set_xscale("log")
    if log_y:
        ax.set_yscale("log")
    return sc


def fit_line(ax, x, y, log: bool = False, color: str = PALETTE["wine"]) -> tuple[float, float]:
    """Vẽ đường hồi quy OLS (trên log10 nếu ``log``) và trả (slope, intercept)."""
    x, y = np.asarray(x, float), np.asarray(y, float)
    m = np.isfinite(x) & np.isfinite(y)
    if log:
        m &= (x > 0) & (y > 0)
        xs, ys = np.log10(x[m]), np.log10(y[m])
    else:
        xs, ys = x[m], y[m]
    slope, inter = np.polyfit(xs, ys, 1)
    grid = np.linspace(xs.min(), xs.max(), 100)
    yy = slope * grid + inter
    ax.plot(10 ** grid if log else grid, 10 ** yy if log else yy, color=color, lw=2.6, ls="--",
            label=f"OLS{' log–log' if log else ''}: hệ số = {slope:.2f}")
    return float(slope), float(inter)


def boxplot(ax, groups: Mapping[str, Sequence[float]], colors: Sequence[str] | None = None,
            log_y: bool = False, showfliers: bool = False):
    """Boxplot nhiều nhóm, hộp tô màu đậm, trung vị trắng."""
    colors = colors or SEQ_COLORS
    bp = ax.boxplot([pd.Series(v).dropna() for v in groups.values()], patch_artist=True,
                    showfliers=showfliers, widths=0.6,
                    medianprops={"color": "white", "lw": 2.2},
                    whiskerprops={"lw": 1.6}, capprops={"lw": 1.6},
                    flierprops={"marker": ".", "ms": 3, "alpha": 0.4})
    for patch, c in zip(bp["boxes"], colors):
        patch.set_facecolor(c)
        patch.set_edgecolor("black")
        patch.set_linewidth(1.2)
    ax.set_xticks(range(1, len(groups) + 1), list(groups.keys()))
    if log_y:
        ax.set_yscale("log")
    return bp


def pareto(ax, labels: Sequence[str], values: Sequence[float], threshold: float = 80.0,
           color: str = PALETTE["blue"], line_color: str = PALETTE["wine"]):
    """Biểu đồ Pareto: cột giảm dần + đường tỷ trọng lũy kế (trục phải)."""
    order = np.argsort(values)[::-1]
    vals = np.asarray(values, float)[order]
    labs = np.asarray(labels)[order]
    cum = vals.cumsum() / vals.sum() * 100
    x = np.arange(len(vals))
    ax.bar(x, vals, color=color, edgecolor="black", linewidth=0.6)
    ax.set_xticks(x, labs, rotation=90, fontsize=8)
    ax2 = ax.twinx()
    ax2.plot(x, cum, color=line_color, lw=2.6, marker="o", ms=3)
    ax2.axhline(threshold, color=PALETTE["gray"], ls=":", lw=1.8)
    k = int(min((cum < threshold).sum(), len(cum) - 1))
    ax2.axvline(k, color=PALETTE["gray"], ls=":", lw=1.8)
    ax2.text(k + 0.5, threshold - 8, f"{k + 1} phần tử ≈ {threshold:.0f}%", color=line_color,
             fontweight="bold")
    ax2.set_ylim(0, 105)
    ax2.yaxis.set_major_formatter(PercentFormatter())
    ax2.spines["right"].set_visible(True)
    ax2.set_ylabel("Tỷ trọng lũy kế")
    return ax2
