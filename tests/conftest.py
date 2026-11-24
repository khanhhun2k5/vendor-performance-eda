"""Cho phép `import src` khi chạy pytest từ thư mục gốc dự án."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
