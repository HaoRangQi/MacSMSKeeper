#!/usr/bin/env python3
"""从 CHANGELOG.md 提取指定版本的小节。

用法：python3 scripts/changelog-section.py <版本号>
提取不到时以退出码 1 结束（调用方可回退到自动生成的说明）。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: changelog-section.py <版本号>", file=sys.stderr)
        return 2

    version = sys.argv[1]
    path = Path(__file__).resolve().parent.parent / "CHANGELOG.md"
    if not path.exists():
        return 1

    text = path.read_text(encoding="utf-8")
    m = re.search(
        rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## \[|\Z)",
        text, re.S | re.M,
    )
    if not m:
        print(f"CHANGELOG 里找不到 {version} 的小节", file=sys.stderr)
        return 1

    print(m.group(1).strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
