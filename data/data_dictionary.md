# Từ điển dữ liệu — Vendor Performance Analysis

> **Nguồn:** Kaggle — [Vendor Performance Analysis (harshmadhavan)](https://www.kaggle.com/datasets/harshmadhavan/vendor-performance-analysis)
> **Bản lưu cục bộ:** `data/raw/` (7 file CSV + `inventory.db` là SQLite chứa đúng 7 bảng tương ứng)
> **Bối cảnh:** dữ liệu mô phỏng chuỗi bán lẻ rượu bia (liquor & wine) gồm ~80 cửa hàng, năm tài chính **2024** (01/01/2024 – 31/12/2024).
> **Cách lập:** mô tả cột dựa trên tên cột + kiểm tra trực tiếp dữ liệu raw (số dòng, null, giá trị min/max, kiểm chứng công thức bằng SQL trên `inventory.db`). Những điểm là **suy luận** (không có tài liệu gốc xác nhận) được ghi rõ.
> **Ngày lập:** 24/11/2026

---

## 1. Tổng quan các bảng

| Bảng / file | 1 dòng là… | Số dòng | Số cột | Dung lượng CSV | Vai trò |
| --- | --- | ---: | ---: | ---: | --- |
| `begin_inventory` | 1 mặt hàng tại 1 cửa hàng, ngày đầu kỳ | 206 529 | 9 | 17,4 MB | Tồn kho đầu kỳ (01/01/2024) |
| `end_inventory` | 1 mặt hàng tại 1 cửa hàng, ngày cuối kỳ | 224 489 | 9 | 19,0 MB | Tồn kho cuối kỳ (31/12/2024) |
| `purchase_prices` | 1 mã sản phẩm (Brand) | 12 261 | 9 | 1,0 MB | Danh mục sản phẩm: giá bán lẻ, giá mua, nhà cung cấp |
| `purchases` | 1 dòng hàng trong 1 đơn mua (PO) giao về 1 cửa hàng | 2 372 474 | 16 | 361,6 MB | Giao dịch mua hàng chi tiết |
| `sales` | 1 mặt hàng tại 1 cửa hàng trong 1 ngày | 12 825 363 | 14 | 1,6 GB | Giao dịch bán hàng (tổng theo ngày) |
| `vendor_invoice` | 1 hóa đơn = 1 đơn mua (PONumber) | 5 543 | 10 | 0,5 MB | Hóa đơn NCC, chi phí vận chuyển |
| `vendor_sales_summary` | 1 cặp (NCC, Brand) | 10 692 | 18 | 2,1 MB | Bảng **tổng hợp/đã tính sẵn** KPI theo NCC – sản phẩm |

**Quy ước chung**

| Hạng mục | Quy ước |
| --- | --- |
| Tiền tệ | **USD ($)**, 2 chữ số thập phân (trừ các cột đã tính trong `vendor_sales_summary`) |
| Số lượng | **chai/đơn vị bán lẻ** (unit). Sản phẩm dạng “4 Pk” được tính là 1 đơn vị (1 lốc) |
| Dung tích | **mL** (cột `Volume`); cột `Size` là chuỗi mô tả tự do |
| Ngày | Chuỗi ISO `YYYY-MM-DD`, lưu dạng `TEXT` trong SQLite → cần ép kiểu `datetime` khi phân tích |
| Chuỗi tên NCC | `VendorName` trong bảng gốc **bị đệm khoảng trắng cuối** (độ dài cố định) → cần `strip()` trước khi join/group (riêng `vendor_sales_summary` đã được strip) |
| Kiểu dữ liệu | Cột “Kiểu SQLite” = kiểu khai báo trong `inventory.db`; cột “Kiểu pandas đề xuất” = kiểu nên dùng sau khi làm sạch |

---

## 2. Sơ đồ quan hệ (khóa nối)

```
                        purchase_prices (Brand – PK)
                               │ Brand
     ┌─────────────────────────┼──────────────────────────┬────────────────────┐
     │                         │                          │                    │
begin_inventory          purchases ────PONumber──── vendor_invoice     vendor_sales_summary
end_inventory      (InventoryId, Brand,          (PONumber – PK,        (VendorNumber, Brand)
(InventoryId – PK)  VendorNumber, PONumber)        VendorNumber)
     │                         │
     └──── InventoryId ────────┴──────── sales (InventoryId, Brand, VendorNo)
```

| Khóa | Ý nghĩa | Dùng để nối |
| --- | --- | --- |
| `InventoryId` | `{Store}_{City}_{Brand}` — 1 sản phẩm tại 1 cửa hàng | inventory ↔ purchases ↔ sales |
| `Brand` | Mã sản phẩm (SKU), duy nhất trong `purchase_prices` | mọi bảng trừ `vendor_invoice` |
| `VendorNumber` / `VendorNo` | Mã nhà cung cấp (**tên cột khác nhau**: `sales` dùng `VendorNo`) | purchases, sales, vendor_invoice, purchase_prices, vendor_sales_summary |
| `PONumber` | Số đơn đặt hàng, duy nhất trong `vendor_invoice` | purchases ↔ vendor_invoice |
| `Store` | Mã cửa hàng (1–81); mỗi Store chỉ gắn với 1 City | inventory, purchases, sales |

---

## 3. Chi tiết từng bảng

### 3.1. `begin_inventory` — Tồn kho đầu kỳ

| Cột | Ý nghĩa | Kiểu SQLite | Kiểu pandas đề xuất | Đơn vị / định dạng | Miền giá trị quan sát | Null | Ghi chú |
| --- | --- | --- | --- | --- | --- | ---: | --- |
| `InventoryId` | Mã tồn kho = `Store_City_Brand` | TEXT | `string` | — | 206 529 giá trị khác nhau | 0 | **Khóa chính** của bảng |
| `Store` | Mã cửa hàng | BIGINT | `int16` / `category` | — | 1 – 79 (79 cửa hàng) | 0 | |
| `City` | Thành phố của cửa hàng | TEXT | `category` | — | 67 thành phố | 0 | Tên giả lập (HARDERSFIELD, …) |
| `Brand` | Mã sản phẩm | BIGINT | `int32` | — | 58 – 90 090 (8 094 mã) | 0 | FK → `purchase_prices.Brand` |
| `Description` | Tên sản phẩm | TEXT | `string` | — | 7 291 tên | 0 | Một tên có thể ứng với nhiều Brand (khác dung tích) |
| `Size` | Quy cách đóng chai | TEXT | `category` | chuỗi: `750mL`, `1.5L`, `Liter`, `50mL 4 Pk`… | 41 giá trị | 0 | Định dạng không đồng nhất (xem §4) |
| `onHand` | Số lượng tồn kho thực tế | BIGINT | `int32` | chai | 0 – 1 251 | 0 | |
| `Price` | Giá bán lẻ niêm yết / đơn vị | FLOAT | `float64` | USD | 0,00 – 13 999,90 | 0 | Có giá = 0 (bất thường) |
| `startDate` | Ngày chụp tồn kho | TEXT | `datetime64` | `YYYY-MM-DD` | chỉ 1 giá trị: `2024-01-01` | 0 | Hằng số |

### 3.2. `end_inventory` — Tồn kho cuối kỳ

Cấu trúc giống `begin_inventory`, khác ở các điểm sau:

| Cột | Khác biệt so với `begin_inventory` |
| --- | --- |
| `Store` | 1 – 81 (80 cửa hàng — có thêm cửa hàng mới mở trong năm) |
| `City` | **1 284 dòng null**, tất cả thuộc `Store = 46` → điền lại từ bảng khác hoặc từ `InventoryId` |
| `Brand` | 9 653 mã (58 – 90 631) |
| `Size` | 47 giá trị |
| `onHand` | 0 – 3 676 chai |
| `Price` | 0,49 – 13 999,90 USD |
| `endDate` (thay `startDate`) | chỉ 1 giá trị: `2024-12-31` |

### 3.3. `purchase_prices` — Danh mục sản phẩm & giá

| Cột | Ý nghĩa | Kiểu SQLite | Kiểu pandas đề xuất | Đơn vị / định dạng | Miền giá trị quan sát | Null | Ghi chú |
| --- | --- | --- | --- | --- | --- | ---: | --- |
| `Brand` | Mã sản phẩm | BIGINT | `int32` | — | 58 – 90 631 (12 261 mã) | 0 | **Khóa chính** |
| `Description` | Tên sản phẩm | TEXT | `string` | — | 11 114 tên | 1 | |
| `Price` | Giá bán lẻ đề xuất / đơn vị | FLOAT | `float64` | USD | 0,00 – 13 999,90 | 0 | Trong `vendor_sales_summary` gọi là `ActualPrice` |
| `Size` | Quy cách đóng chai | TEXT | `category` | chuỗi, vd `750mL`, `187mL 4 Pk` | 56 giá trị | 1 | Có giá trị `Unknown`, `1500ml` (chữ thường) |
| `Volume` | Dung tích 1 chai | **TEXT** | `float64` (sau làm sạch) | mL | 20 – 20 000 | 1 | Chứa chuỗi `Unknown` nên bị lưu dạng TEXT |
| `Classification` | Nhóm sản phẩm | BIGINT | `category` | mã | {1, 2} | 0 | **Suy luận:** 1 = rượu mạnh (spirits/liquor), 2 = rượu vang (wine). 1: 3 568 SP, 2: 8 693 SP |
| `PurchasePrice` | Giá mua từ NCC / đơn vị | FLOAT | `float64` | USD | 0,00 – 11 111,03 | 0 | Giá vốn |
| `VendorNumber` | Mã NCC | BIGINT | `int32` | — | 131 mã | 0 | |
| `VendorName` | Tên NCC | TEXT | `string` | — | 136 tên | 0 | Có khoảng trắng thừa; số tên > số mã ⇒ 1 mã có nhiều cách viết tên |

### 3.4. `purchases` — Giao dịch mua hàng

| Cột | Ý nghĩa | Kiểu SQLite | Kiểu pandas đề xuất | Đơn vị / định dạng | Miền giá trị quan sát | Null | Ghi chú |
| --- | --- | --- | --- | --- | --- | ---: | --- |
| `InventoryId` | Mã tồn kho `Store_City_Brand` | TEXT | `string` | — | 245 907 giá trị | 0 | FK → inventory |
| `Store` | Mã cửa hàng nhận hàng | BIGINT | `int16` | — | 1 – 81 | 0 | |
| `Brand` | Mã sản phẩm | BIGINT | `int32` | — | 10 664 mã | 0 | |
| `Description` | Tên sản phẩm | TEXT | `string` | — | 9 652 tên | 0 | |
| `Size` | Quy cách | TEXT | `category` | chuỗi | 51 giá trị | 3 | |
| `VendorNumber` | Mã NCC | BIGINT | `int32` | — | 126 mã (2 – 201 359) | 0 | |
| `VendorName` | Tên NCC | TEXT | `string` | — | 129 tên | 0 | Cần `strip()` |
| `PONumber` | Số đơn đặt hàng | BIGINT | `int32` | — | 8 106 – 13 661 (5 543 PO) | 0 | FK → `vendor_invoice` |
| `PODate` | Ngày đặt hàng | TEXT | `datetime64` | `YYYY-MM-DD` | 2023-12-20 – 2024-12-23 | 0 | Có PO đặt từ cuối 2023 |
| `ReceivingDate` | Ngày cửa hàng nhận hàng | TEXT | `datetime64` | `YYYY-MM-DD` | 2024-01-01 – 2024-12-31 | 0 | Trung bình ~10 ngày sau `PODate` |
| `InvoiceDate` | Ngày xuất hóa đơn | TEXT | `datetime64` | `YYYY-MM-DD` | 2024-01-04 – 2025-01-10 | 0 | |
| `PayDate` | Ngày thanh toán cho NCC | TEXT | `datetime64` | `YYYY-MM-DD` | 2024-02-04 – 2025-02-19 | 0 | Trung bình ~35 ngày sau `InvoiceDate` |
| `PurchasePrice` | Giá mua / đơn vị | FLOAT | `float64` | USD | 0,00 – 5 681,81 | 0 | 153 dòng giá = 0 |
| `Quantity` | Số lượng mua | BIGINT | `int32` | chai | 1 – 3 816 | 0 | |
| `Dollars` | Thành tiền mua | FLOAT | `float64` | USD | 0,00 – 50 175,70 | 0 | **= `PurchasePrice × Quantity`** (đã kiểm chứng: 0 dòng lệch) |
| `Classification` | Nhóm sản phẩm | BIGINT | `category` | mã | {1, 2} | 0 | Như `purchase_prices` |

### 3.5. `sales` — Giao dịch bán hàng

| Cột | Ý nghĩa | Kiểu SQLite | Kiểu pandas đề xuất | Đơn vị / định dạng | Miền giá trị quan sát | Null | Ghi chú |
| --- | --- | --- | --- | --- | --- | ---: | --- |
| `InventoryId` | Mã tồn kho `Store_City_Brand` | TEXT | `string` | — | 267 552 giá trị | 0 | |
| `Store` | Mã cửa hàng bán | BIGINT | `int16` | — | 1 – 81 | 0 | |
| `Brand` | Mã sản phẩm | BIGINT | `int32` | — | 11 237 mã | 0 | |
| `Description` | Tên sản phẩm | TEXT | `string` | — | 10 182 tên | 0 | |
| `Size` | Quy cách | TEXT | `category` | chuỗi | 51 giá trị | 0 | |
| `SalesQuantity` | Số lượng bán trong ngày | BIGINT | `int32` | chai | 1 – 1 231 | 0 | |
| `SalesDollars` | Doanh thu trong ngày | FLOAT | `float64` | USD | 0,00 – 26 061,14 | 0 | ≈ `SalesQuantity × SalesPrice` |
| `SalesPrice` | Giá bán / đơn vị | FLOAT | `float64` | USD | 0,00 – 5 799,99 | 0 | 55 dòng giá = 0 |
| `SalesDate` | Ngày bán | TEXT | `datetime64` | `YYYY-MM-DD` | 2024-01-01 – 2024-12-31 (364 ngày) | 0 | |
| `Volume` | Dung tích 1 chai | FLOAT | `float64` | mL | 50 – 20 000 | 0 | Kiểu số (khác `purchase_prices`) |
| `Classification` | Nhóm sản phẩm | BIGINT | `category` | mã | {1, 2} | 0 | |
| `ExciseTax` | Thuế tiêu thụ đặc biệt của giao dịch | FLOAT | `float64` | USD | 0,01 – 1 260,52 | 0 | **Suy luận:** tính theo dung tích × số lượng × mức thuế của nhóm (vd 1 chai 750 mL rượu mạnh ≈ $0,79) |
| `VendorNo` | Mã NCC | BIGINT | `int32` | — | 127 mã | 0 | **Tên khác** `VendorNumber` ở bảng khác |
| `VendorName` | Tên NCC | TEXT | `string` | — | 130 tên | 0 | Cần `strip()` |

> ⚠️ `sales.csv` ~1,6 GB / 12,8 triệu dòng: nên đọc bằng SQL trên `inventory.db` hoặc `pd.read_csv(..., chunksize=..., dtype=...)`.

### 3.6. `vendor_invoice` — Hóa đơn nhà cung cấp

| Cột | Ý nghĩa | Kiểu SQLite | Kiểu pandas đề xuất | Đơn vị / định dạng | Miền giá trị quan sát | Null | Ghi chú |
| --- | --- | --- | --- | --- | --- | ---: | --- |
| `VendorNumber` | Mã NCC | BIGINT | `int32` | — | 126 mã | 0 | |
| `VendorName` | Tên NCC | TEXT | `string` | — | 129 tên | 0 | Cần `strip()` |
| `InvoiceDate` | Ngày hóa đơn | TEXT | `datetime64` | `YYYY-MM-DD` | 2024-01-04 – 2025-01-10 | 0 | |
| `PONumber` | Số đơn đặt hàng | BIGINT | `int32` | — | 5 543 giá trị | 0 | **Khóa chính** |
| `PODate` | Ngày đặt hàng | TEXT | `datetime64` | `YYYY-MM-DD` | 2023-12-20 – 2024-12-23 | 0 | |
| `PayDate` | Ngày thanh toán | TEXT | `datetime64` | `YYYY-MM-DD` | 2024-02-04 – 2025-02-19 | 0 | |
| `Quantity` | Tổng số lượng trên hóa đơn | BIGINT | `int32` | chai | 1 – 141 660 | 0 | |
| `Dollars` | Tổng tiền hàng trên hóa đơn | FLOAT | `float64` | USD | 4,14 – 1 660 435,88 | 0 | Không gồm phí vận chuyển |
| `Freight` | Phí vận chuyển | FLOAT | `float64` | USD | 0,02 – 8 468,22 | 0 | Nguồn duy nhất của chi phí vận chuyển |
| `Approval` | Người duyệt hóa đơn | TEXT | `category` | — | chỉ 1 giá trị: `Frank Delahunt` | **5 169 (93,3%)** | Rỗng = chưa có/không ghi người duyệt |

> ⚠️ **Lệch dữ liệu: số PO trên hóa đơn bị xáo trộn.**
> - Với 1 336/5 543 hóa đơn (toàn bộ từ `PONumber` 12311, tức PODate ≥ 25/09/2024), `VendorNumber`/`Quantity`/`Dollars` trên hóa đơn **không khớp** PO cùng số trong `purchases`. Chúng khớp đúng với **một PO khác đặt cùng thời điểm**.
> - `PODate` trên các hóa đơn này lệch ±5 ngày; `InvoiceDate`/`PayDate` cũng khác ngày ghi trên dòng mua.
> - **Không nối `vendor_invoice` theo `PONumber`.** Hãy ghép theo (`VendorNumber`, `Quantity`, `Dollars`) và chọn PODate gần nhất: ghép được 100 %, xem bảng `map_invoice_po` do `sql/build/03_purchase_marts.sql` tạo.
> - Nếu nối sai thì phí vận chuyển theo NCC chỉ khớp 9/126 NCC so với `vendor_sales_summary`; ghép đúng thì khớp 126/126.

### 3.7. `vendor_sales_summary` — Bảng tổng hợp KPI theo NCC × sản phẩm

Bảng **dẫn xuất** (đã được tạo sẵn trong dataset từ `purchases`, `sales`, `purchase_prices`, `vendor_invoice`). Các công thức dưới đây đã được **kiểm chứng trên toàn bộ 10 692 dòng** (sai lệch = 0).

| Cột | Ý nghĩa | Kiểu SQLite | Kiểu pandas | Đơn vị | Miền giá trị | Công thức / nguồn |
| --- | --- | --- | --- | --- | --- | --- |
| `VendorNumber` | Mã NCC | INTEGER | `int32` | — | 126 mã | `purchases.VendorNumber` |
| `VendorName` | Tên NCC (đã strip) | TEXT | `string` | — | 128 tên | |
| `Brand` | Mã sản phẩm | INTEGER | `int32` | — | 10 663 mã | |
| `Description` | Tên sản phẩm | TEXT | `string` | — | | |
| `PurchasePrice` | Giá mua / đơn vị | REAL | `float64` | USD | 0,36 – 5 681,81 | Chỉ giữ dòng có giá mua > 0 |
| `ActualPrice` | Giá bán lẻ niêm yết / đơn vị | REAL | `float64` | USD | 0,49 – 7 499,99 | `= purchase_prices.Price` (khớp 100%) |
| `Volume` | Dung tích | REAL | `float64` | mL | 50 – 20 000 | |
| `TotalPurchaseQuantity` | Tổng số lượng mua | INTEGER | `int64` | chai | 1 – 337 660 | `Σ purchases.Quantity` |
| `TotalPurchaseDollars` | Tổng chi phí mua | REAL | `float64` | USD | 0,71 – 3 811 251,60 | `Σ purchases.Dollars` |
| `TotalSalesQuantity` | Tổng số lượng bán | REAL | `float64` | chai | 0 – 334 939 | `Σ sales.SalesQuantity`; = 0 nếu không bán được |
| `TotalSalesPrice` | Tổng các đơn giá bán | REAL | `float64` | USD | 0 – 672 819,31 | `Σ sales.SalesPrice` — **không có ý nghĩa kinh tế trực tiếp** (cộng đơn giá), tránh dùng làm doanh thu |
| `TotalSalesDollars` | Tổng doanh thu | REAL | `float64` | USD | 0 – 5 101 919,51 | `Σ sales.SalesDollars` |
| `TotalExciseTax` | Tổng thuế tiêu thụ đặc biệt | REAL | `float64` | USD | 0 – 368 242,80 | `Σ sales.ExciseTax` |
| `FreightCost` | Phí vận chuyển của **NCC** | REAL | `float64` | USD | 0,09 – 257 032,07 | `Σ vendor_invoice.Freight` theo NCC — **lặp lại cho mọi Brand của cùng NCC**, không cộng dồn theo Brand |
| `GrossProfit` | Lợi nhuận gộp | REAL | `float64` | USD | −52 002,78 – 1 290 667,91 | `TotalSalesDollars − TotalPurchaseDollars` (2 127 dòng âm) |
| `ProfitMargin` | Biên lợi nhuận gộp | REAL | `float64` | **%** | −∞ – 99,72 | `GrossProfit / TotalSalesDollars × 100`; **178 dòng = −inf** (khi `TotalSalesDollars = 0`) |
| `StockTurnover` | Vòng quay hàng (tỷ lệ bán/mua theo số lượng) | REAL | `float64` | lần (không đơn vị) | 0 – 274,5 | `TotalSalesQuantity / TotalPurchaseQuantity`; > 1 ⇒ bán cả hàng tồn đầu kỳ |
| `SalestoPurchaseRatio` | Tỷ lệ doanh thu / chi phí mua | REAL | `float64` | lần | 0 – 352,93 | `TotalSalesDollars / TotalPurchaseDollars` |

---

## 4. Vấn đề chất lượng dữ liệu cần xử lý

| # | Vấn đề | Bảng / cột | Quy mô | Đề xuất xử lý |
| --- | --- | --- | --- | --- |
| 1 | Khoảng trắng thừa ở tên NCC | `VendorName` (mọi bảng gốc) | toàn bộ | `str.strip()` |
| 2 | Tên cột mã NCC không thống nhất | `sales.VendorNo` vs `VendorNumber` | — | Đổi tên về `VendorNumber` |
| 3 | `Size` không chuẩn hóa | `Size` | `1.5L`, `1500mL`, `1500ml`, `Liter`, `750mL 4 Pk`, `750mL + 3/`, `Unknown` | Tách thành dung tích (mL) + số chai/lốc; dùng `Volume` khi cần số |
| 4 | `Volume` lưu dạng chuỗi có `Unknown` | `purchase_prices.Volume` | 1 null + giá trị `Unknown` | `pd.to_numeric(errors='coerce')` |
| 5 | City bị thiếu | `end_inventory.City` | 1 284 dòng (Store 46) | Điền theo `Store` từ bảng khác / tách từ `InventoryId` |
| 6 | Giá = 0 | `purchases.PurchasePrice` (153), `sales.SalesPrice` (55), `Price` | nhỏ | Loại hoặc gắn cờ (hàng tặng/khuyến mãi?) |
| 7 | Hầu hết hóa đơn không có người duyệt | `vendor_invoice.Approval` | 93,3% null | Coi null = “Chưa duyệt/không ghi nhận”, không impute |
| 8 | Số PO trên hóa đơn bị xáo trộn (gây ra cảnh “hóa đơn lệch chi tiết mua”) | `vendor_invoice` vs `purchases` | 1 336/5 543 PO (24 %), từ 25/09/2024 | Ghép lại theo (NCC, SL, tiền) + PODate gần nhất (`map_invoice_po`) |
| 9 | `ProfitMargin = −inf` | `vendor_sales_summary` | 178 dòng | Thay bằng NaN hoặc loại (sản phẩm không bán được) |
| 10 | Lỗ gộp | `vendor_sales_summary.GrossProfit < 0` | 2 127 dòng | Không phải lỗi: thường do mua nhiều hơn bán (hàng tồn) — phân tích riêng |
| 11 | `FreightCost` ở cấp NCC | `vendor_sales_summary` | — | Không `sum` theo Brand; lấy `max/first` theo NCC hoặc phân bổ theo tỷ trọng `TotalPurchaseDollars` |
| 12 | Ngày lưu dạng chuỗi | mọi cột `*Date` | — | `pd.to_datetime(format='%Y-%m-%d')` |
| 13 | Ngày nằm ngoài năm 2024 | `PODate` (từ 2023-12-20), `InvoiceDate`/`PayDate` (đến 2025) | — | Hợp lệ (đơn vắt qua kỳ); lọc theo `ReceivingDate`/`SalesDate` nếu cần đúng kỳ |
| 14 | Ngày thiếu dữ liệu | `sales` không có dòng nào ngày 2024-03-27 và 2024-11-24; `purchases` không nhận hàng ngày 2024-03-27 và 2024-12-25 | 2/366 ngày | 27/03 vắng mặt ở cả hai file nên nhiều khả năng mất dữ liệu; lưu ý khi so sánh theo ngày/tuần |
| 15 | `Size` viết khác nhau giữa file | danh mục ghi `1500mL`, giao dịch/tồn kho ghi `1.5L`, `Liter` | ~1 400 SP; chỉ 33 SP khác dung tích thật | Dùng `Volume` (mL) khi cần số |
| 16 | Giá danh mục ≠ giá thực tế | `sales.SalesPrice`, `*_inventory.Price` vs `purchase_prices.Price` | 46 % dòng bán, 43–50 % dòng tồn kho | Giá danh mục chỉ là giá tham chiếu; doanh thu lấy từ `SalesDollars`. Giá mua thì luôn khớp danh mục. |
| 17 | `Description` khác danh mục | `begin_inventory` vs `purchase_prices` | 2 755 dòng (vd “Glass Pack” ↔ “VAP”) | Nối theo `Brand`, không theo tên |

> ✅ **Các kiểm tra đạt** (xem `notebook/01` §5–6, bảng `dq_consistency`):
> - Mọi ngày đúng định dạng và thứ tự đặt → nhận → hóa đơn → thanh toán.
> - Thành tiền = đơn giá × số lượng.
> - Không trùng khóa, không có Brand mồ côi, `InventoryId` luôn đúng mẫu `Store_City_Brand`.
> - **Tồn kho cân đối tuyệt đối** (đầu kỳ + mua − bán = cuối kỳ) cho cả 276 389 `InventoryId`.
> - 20 347 `InventoryId` không có trong ảnh chụp tồn kho là hàng mua rồi bán hết trong năm.

---

## 5. Chỉ số phái sinh thường dùng (gợi ý)

| Chỉ số | Công thức | Đơn vị |
| --- | --- | --- |
| Thời gian giao hàng (lead time) | ngày nhận **cuối** của PO − `PODate` (nhận đủ hàng; 5 000/5 543 PO giao nhiều đợt) | ngày (TB ≈ 9,9; nhận lô đầu TB ≈ 6,0; TB theo dòng ≈ 7,7) |
| Thời gian thanh toán | `PayDate − InvoiceDate` | ngày (TB ≈ 35,5) |
| Biến động tồn kho | `end.onHand − begin.onHand` theo `InventoryId` | chai |
| Giá trị hàng tồn | `onHand × Price` | USD |
| Tỷ lệ phí vận chuyển | `Freight / Dollars` (theo hóa đơn) | % |
| Lợi nhuận ròng sau thuế & vận chuyển (ước lượng) | `GrossProfit − TotalExciseTax − FreightCost phân bổ` | USD |
