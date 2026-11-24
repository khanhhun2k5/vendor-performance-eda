"""Test tích hợp: chạy toàn bộ pipeline SQL (CSV → staging → sql/build/01…08) trên bộ CSV tổng hợp nhỏ.

Dữ liệu được dựng cố ý có các lỗi đã gặp ở dữ liệu thật:
* vendor_invoice bị XÁO số PO (hóa đơn PO 100 mang NCC/SL/tiền của PO 101 và ngược lại);
* end_inventory thiếu City; purchase_prices.Volume = 'Unknown'; VendorName có khoảng trắng thừa;
* vendor_sales_summary có ProfitMargin = -inf; 1 cặp (Brand, NCC) chỉ có bán, không có mua.
"""
import csv
import sqlite3
from contextlib import closing

import pytest

from src import data_loader as dl

H = {
    "begin_inventory": ["InventoryId", "Store", "City", "Brand", "Description", "Size", "onHand", "Price", "startDate"],
    "end_inventory": ["InventoryId", "Store", "City", "Brand", "Description", "Size", "onHand", "Price", "endDate"],
    "purchase_prices": ["Brand", "Description", "Price", "Size", "Volume", "Classification", "PurchasePrice",
                        "VendorNumber", "VendorName"],
    "purchases": ["InventoryId", "Store", "Brand", "Description", "Size", "VendorNumber", "VendorName", "PONumber",
                  "PODate", "ReceivingDate", "InvoiceDate", "PayDate", "PurchasePrice", "Quantity", "Dollars",
                  "Classification"],
    "sales": ["InventoryId", "Store", "Brand", "Description", "Size", "SalesQuantity", "SalesDollars", "SalesPrice",
              "SalesDate", "Volume", "Classification", "ExciseTax", "VendorNo", "VendorName"],
    "vendor_invoice": ["VendorNumber", "VendorName", "InvoiceDate", "PONumber", "PODate", "PayDate", "Quantity",
                       "Dollars", "Freight", "Approval"],
    "vendor_sales_summary": ["VendorNumber", "VendorName", "Brand", "Description", "PurchasePrice", "ActualPrice",
                             "Volume", "TotalPurchaseQuantity", "TotalPurchaseDollars", "TotalSalesQuantity",
                             "TotalSalesPrice", "TotalSalesDollars", "TotalExciseTax", "FreightCost", "GrossProfit",
                             "ProfitMargin", "StockTurnover", "SalestoPurchaseRatio"],
}

ROWS = {
    "purchase_prices": [
        [1, "Vodka A", 20.0, "1.75L", 1750, 1, 12.0, 10, "VENDOR TEN   "],
        [2, "Wine B", 10.0, "750mL", "Unknown", 2, 6.0, 20, "VENDOR TWENTY "],
        [3, "Gin C", 15.0, "750mL", 750, 1, 9.0, 10, "VENDOR TEN   "],
    ],
    "begin_inventory": [
        ["1_ALPHA_1", 1, "ALPHA", 1, "Vodka A", "1.75L", 5, 20.0, "2024-01-01"],
        ["1_ALPHA_3", 1, "ALPHA", 3, "Gin C", "750mL", 4, 15.0, "2024-01-01"],
    ],
    "end_inventory": [
        ["1_ALPHA_1", 1, "ALPHA", 1, "Vodka A", "1.75L", 3, 20.0, "2024-12-31"],
        ["1_ALPHA_2", 1, "", 2, "Wine B", "750mL", 2, 10.0, "2024-12-31"],      # City trống
    ],
    "purchases": [
        ["1_ALPHA_1", 1, 1, "Vodka A", "1.75L", 10, "VENDOR TEN   ", 100, "2024-01-02", "2024-01-05",
         "2024-01-10", "2024-02-10", 12.0, 4, 48.0, 1],
        ["1_ALPHA_2", 1, 2, "Wine B", "750mL", 20, "VENDOR TWENTY ", 101, "2024-01-03", "2024-01-06",
         "2024-01-11", "2024-02-11", 6.0, 2, 12.0, 2],
    ],
    "sales": [   # tồn đầu 5 + mua 4 − bán 6 = cuối 3 ; Gin C: đầu 4 − bán 4 = 0 (chỉ có bán)
        ["1_ALPHA_1", 1, 1, "Vodka A", "1.75L", 6, 120.0, 20.0, "2024-01-07", 1750.0, 1, 11.03, 10, "VENDOR TEN   "],
        ["1_ALPHA_3", 1, 3, "Gin C", "750mL", 4, 60.0, 15.0, "2024-01-08", 750.0, 1, 3.15, 10, "VENDOR TEN   "],
    ],
    "vendor_invoice": [   # số PO bị đảo: hóa đơn 100 thực ra là của PO 101 và ngược lại
        [20, "VENDOR TWENTY ", "2024-01-11", 100, "2024-01-04", "2024-02-11", 2, 12.0, 0.06, ""],
        [10, "VENDOR TEN   ", "2024-01-10", 101, "2024-01-02", "2024-02-10", 4, 48.0, 0.24, "Frank Delahunt"],
    ],
    "vendor_sales_summary": [
        [10, "VENDOR TEN", 1, "Vodka A", 12.0, 20.0, 1750.0, 4, 48.0, 6.0, 20.0, 120.0, 11.03, 0.24, 72.0, 60.0,
         1.5, 2.5],
        [20, "VENDOR TWENTY", 2, "Wine B", 6.0, 10.0, 750.0, 2, 12.0, 0.0, 0.0, 0.0, 0.0, 0.06, -12.0, "-inf",
         0.0, 0.0],
    ],
}


@pytest.fixture(scope="module")
def built(tmp_path_factory):
    root = tmp_path_factory.mktemp("proj")
    raw = root / "raw"
    raw.mkdir()
    for name, header in H.items():
        with open(raw / f"{name}.csv", "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(header)
            w.writerows(ROWS[name])
    mp = pytest.MonkeyPatch()
    mp.setattr(dl, "RAW_DIR", raw)
    mp.setattr(dl, "STAGING_DB", root / "staging.db")
    mp.setattr(dl, "MART_DB", root / "analytics.db")
    dl._QUERY_CACHE.clear()
    dl.build_marts(force=True, verbose=False)
    yield dl
    dl._QUERY_CACHE.clear()
    mp.undo()


def _one(dl_, sql):
    return dl_.sql(sql).iloc[0, 0]


def test_staging_types_and_nulls(built):
    with closing(built.connect_staging()) as c:
        assert c.execute("SELECT typeof(Store), typeof(Price) FROM begin_inventory").fetchone() == ("integer", "real")
        assert c.execute("SELECT City FROM end_inventory WHERE Brand = 2").fetchone()[0] is None
        assert c.execute("SELECT ProfitMargin FROM ref_vendor_sales_summary WHERE Brand = 2").fetchone()[0] == float("-inf")


def test_dimensions_cleaned(built):
    assert _one(built, "SELECT VendorName FROM dim_vendor WHERE VendorNumber = 10") == "VENDOR TEN"
    assert _one(built, "SELECT Volume FROM dim_product WHERE Brand = 2") is None       # 'Unknown' → NULL
    assert _one(built, "SELECT City FROM dim_store WHERE Store = 1") == "ALPHA"


def test_invoice_rematched_by_business_key(built):
    m = built.sql("SELECT invoice_po, PONumber, match_type FROM map_invoice_po ORDER BY PONumber")
    assert list(m["invoice_po"]) == [101, 100]                  # PO 100 ↔ hóa đơn 101
    assert set(m["match_type"]) == {"ghép lại theo NCC+SL+tiền"}
    po = built.sql("SELECT PONumber, Freight, qty_mismatch FROM mart_po ORDER BY PONumber")
    assert list(po["Freight"]) == [0.24, 0.06]                  # phí VC theo đúng NCC
    assert po["qty_mismatch"].sum() == 0


def test_vendor_freight_matches_reference(built):
    assert _one(built, "SELECT freight FROM mart_vendor_po WHERE VendorNumber = 10") == pytest.approx(0.24)
    dq = built.query("dq_checks", use_cache=False)
    # mọi kiểm chứng với bảng tham chiếu (doanh thu, anti-join 2 chiều, phí VC theo NCC) đều = 0
    assert dq.query("check_id == 14")["n_affected"].sum() == 0


def test_vendor_brand_full_join_and_kpis(built):
    vb = built.sql("SELECT * FROM mart_vendor_brand ORDER BY Brand").set_index("Brand")
    assert vb.loc[1, "gross_profit"] == pytest.approx(72.0)
    assert vb.loc[1, "stock_turnover"] == pytest.approx(1.5)
    assert vb.loc[2, "margin_pct"] is None or vb.loc[2, "margin_pct"] != vb.loc[2, "margin_pct"]   # NULL (không bán)
    assert vb.loc[3, "has_purchase"] == 0                       # chỉ có bán
    assert vb.loc[3, "sales_dollars"] == pytest.approx(60.0)
    assert vb.loc[3, "margin_pct"] != vb.loc[3, "margin_pct"]   # NaN: không có giá vốn
    assert vb["sales_dollars"].sum() == pytest.approx(_one(built, "SELECT SUM(dollars) FROM mart_sales_daily"))


def test_stock_flow_balances(built):
    f = built.sql("SELECT * FROM mart_stock_flow").set_index("InventoryId")
    assert (f["gap"] == 0).all()
    assert f.loc["1_ALPHA_1", ["begin_onhand", "purchased", "sold", "end_onhand"]].tolist() == [5, 4, 6, 3]


def test_dates_and_calendar(built):
    d = built.query("dq_dates", use_cache=False)
    assert d["n_bad_format"].sum() == 0
    cal = built.query("dq_calendar", use_cache=False)
    assert len(cal) == 366                                       # 2024 là năm nhuận
    assert cal["has_sales"].sum() == 2


def test_consistency_table_flags_invoice_error(built):
    c = built.query("dq_consistency", use_cache=False)
    inv = c[c["check_name"].str.startswith("Số PO trên hóa đơn")].iloc[0]
    assert inv["n_affected"] == 2 and inv["severity"] == "Lỗi"
    gap = c[c["check_name"].str.startswith("Cân đối lệch")].iloc[0]
    assert gap["n_affected"] == 0 and gap["severity"] == "Đạt"
    assert c[c["check_group"] == "Số học"]["n_affected"].sum() == 0


def test_query_rejects_unknown_param(built):
    with pytest.raises(TypeError):
        built.query("top_vendors", topn=5)


def test_query_rejects_bad_names(built):
    with pytest.raises(ValueError):
        built.load_sql("../secret")
    with pytest.raises(ValueError):
        built.read_table('mart_po"; DROP TABLE x; --')
