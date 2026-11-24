"""Package hỗ trợ EDA cho bộ dữ liệu Vendor Performance Analysis.

- ``src.config``         : đường dẫn dự án
- ``src.data_loader``    : build ``analytics.db`` từ ``sql/build`` và chạy ``sql/queries``
- ``src.preprocessing``  : làm sạch nhẹ, thống kê mô tả, ngoại lai, Pareto
- ``src.visualization``  : biểu đồ phong cách xuất bản, bảng màu đậm
"""
from . import config, data_loader, preprocessing, visualization  # noqa: F401

__all__ = ["config", "data_loader", "preprocessing", "visualization"]
