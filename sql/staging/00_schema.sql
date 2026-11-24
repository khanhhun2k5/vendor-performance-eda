-- =====================================================================
-- 00_schema.sql — Lược đồ staging cho dữ liệu nạp từ CSV gốc (data/raw/*.csv).
-- Tạo trong data/interim/staging.db bởi src/data_loader.py::build_staging().
--
-- * Kiểu khai báo BIGINT/FLOAT/TEXT ⇒ SQLite tự ép chuỗi CSV sang INTEGER/REAL
--   (type affinity); ô rỗng được nạp thành NULL.
-- * KHÔNG dùng data/raw/inventory.db.
-- * ref_vendor_sales_summary chỉ để ĐỐI CHIẾU (sql/build/07_validation.sql),
--   không bảng mart nào lấy dữ liệu từ nó.
-- =====================================================================

DROP TABLE IF EXISTS begin_inventory;
CREATE TABLE begin_inventory (
    InventoryId TEXT, Store BIGINT, City TEXT, Brand BIGINT, Description TEXT,
    Size TEXT, onHand BIGINT, Price FLOAT, startDate TEXT
);

DROP TABLE IF EXISTS end_inventory;
CREATE TABLE end_inventory (
    InventoryId TEXT, Store BIGINT, City TEXT, Brand BIGINT, Description TEXT,
    Size TEXT, onHand BIGINT, Price FLOAT, endDate TEXT
);

DROP TABLE IF EXISTS purchase_prices;
CREATE TABLE purchase_prices (
    Brand BIGINT, Description TEXT, Price FLOAT, Size TEXT,
    Volume TEXT,                      -- chứa 'Unknown' ⇒ giữ TEXT, ép kiểu ở 01_dimensions.sql
    Classification BIGINT, PurchasePrice FLOAT, VendorNumber BIGINT, VendorName TEXT
);

DROP TABLE IF EXISTS purchases;
CREATE TABLE purchases (
    InventoryId TEXT, Store BIGINT, Brand BIGINT, Description TEXT, Size TEXT,
    VendorNumber BIGINT, VendorName TEXT, PONumber BIGINT,
    PODate TEXT, ReceivingDate TEXT, InvoiceDate TEXT, PayDate TEXT,
    PurchasePrice FLOAT, Quantity BIGINT, Dollars FLOAT, Classification BIGINT
);

DROP TABLE IF EXISTS sales;
CREATE TABLE sales (
    InventoryId TEXT, Store BIGINT, Brand BIGINT, Description TEXT, Size TEXT,
    SalesQuantity BIGINT, SalesDollars FLOAT, SalesPrice FLOAT, SalesDate TEXT,
    Volume FLOAT, Classification BIGINT, ExciseTax FLOAT, VendorNo BIGINT, VendorName TEXT
);

DROP TABLE IF EXISTS vendor_invoice;
CREATE TABLE vendor_invoice (
    VendorNumber BIGINT, VendorName TEXT, InvoiceDate TEXT, PONumber BIGINT,
    PODate TEXT, PayDate TEXT, Quantity BIGINT, Dollars FLOAT, Freight FLOAT, Approval TEXT
);

-- Bảng tham chiếu (chỉ dùng để kiểm chứng kết quả tự tính)
DROP TABLE IF EXISTS ref_vendor_sales_summary;
CREATE TABLE ref_vendor_sales_summary (
    VendorNumber INTEGER, VendorName TEXT, Brand INTEGER, Description TEXT,
    PurchasePrice REAL, ActualPrice REAL, Volume REAL,
    TotalPurchaseQuantity INTEGER, TotalPurchaseDollars REAL,
    TotalSalesQuantity REAL, TotalSalesPrice REAL, TotalSalesDollars REAL,
    TotalExciseTax REAL, FreightCost REAL, GrossProfit REAL,
    ProfitMargin REAL, StockTurnover REAL, SalestoPurchaseRatio REAL
);
