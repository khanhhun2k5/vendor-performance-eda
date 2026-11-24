"""Test các hàm thống kê trong src/preprocessing.py (trường hợp chuẩn, biên, lỗi)."""
import numpy as np
import pandas as pd
import pytest

from src import preprocessing as pp


def test_gini_equal_and_concentrated():
    assert pp.gini([5, 5, 5, 5]) == pytest.approx(0.0)
    # 1 phần tử chiếm hết: Gini = (n-1)/n
    assert pp.gini([0, 0, 0, 10]) == pytest.approx(0.75)


def test_gini_empty_or_zero_is_nan():
    assert np.isnan(pp.gini([]))
    assert np.isnan(pp.gini([0, 0]))


def test_hhi():
    assert pp.hhi([100]) == pytest.approx(10_000)
    assert pp.hhi([50, 50]) == pytest.approx(5_000)


def test_n_to_reach_share_basic_and_cap():
    cum = pd.Series([50.0, 75.0, 90.0, 100.0])
    assert pp.n_to_reach_share(cum, 80) == 3
    assert pp.n_to_reach_share(cum, 50) == 1          # phần tử đầu đã đạt đúng 50 %
    # ngưỡng 100 hoặc sai số float không được trả về n + 1
    assert pp.n_to_reach_share(pd.Series([60.0, 99.9999999]), 100) == 2


def test_n_to_reach_share_ignores_nan():
    assert pp.n_to_reach_share(pd.Series([np.nan, 40.0, 100.0]), 80) == 2


def test_iqr_bounds():
    lo, hi = pp.iqr_bounds(pd.Series([1, 2, 3, 4, 5, 6, 7, 8]))
    q1, q3 = 2.75, 6.25
    assert lo == pytest.approx(q1 - 1.5 * (q3 - q1))
    assert hi == pytest.approx(q3 + 1.5 * (q3 - q1))


def test_outlier_summary_flags_extreme():
    s = pd.DataFrame({"x": [1, 2, 2, 3, 3, 3, 4, 4, 5, 1000]})
    out = pp.outlier_summary(s, ["x"])
    assert out.loc["x", "n_high"] == 1
    assert out.loc["x", "n_low"] == 0


def test_describe_distribution_columns():
    d = pp.describe_distribution(pd.DataFrame({"a": [0, 1, 2, 3, 100]}), ["a"])
    assert d.loc["a", "median"] == 2
    assert d.loc["a", "zero_pct"] == pytest.approx(20.0)
    assert d.loc["a", "skew"] > 1          # lệch phải


def test_fmt_money_sign_and_units():
    assert pp.fmt_money(452_062_952) == "$452.06M"
    assert pp.fmt_money(-321_900_000) == "-$321.90M"
    assert pp.fmt_money(1_500) == "$1.5K"
    assert pp.fmt_money(float("nan")) == "—"


def test_month_label_and_class_name():
    assert list(pp.month_label(pd.Series(["2024-01", "2024-12"]))) == ["Th1", "Th12"]
    df = pp.add_class_name(pd.DataFrame({"Classification": [1, 2]}))
    assert list(df["ClassName"]) == ["Rượu mạnh", "Rượu vang"]


def test_parse_dates_invalid_becomes_nat():
    df = pp.parse_dates(pd.DataFrame({"d": ["2024-02-29", "2024-02-30"]}), ["d"])
    assert df["d"].iloc[0] == pd.Timestamp("2024-02-29")
    assert pd.isna(df["d"].iloc[1])
