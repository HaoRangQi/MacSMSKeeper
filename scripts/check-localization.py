#!/usr/bin/env python3
"""本地化静态检查。

抓两类真实会出事的错误：
1. 词条 key 重复 —— Swift 会把大字典字面量优化成 uniqueKeysWithValues，
   重复 key 在运行时 fatalError（切语言就闪退）。
2. L.t() 用了词条表里不存在的 key —— 会静默回落到中文，
   英文用户看到中文，且没有任何报错。
3. 占位符数量不一致 —— %d/%@ 个数对不上，运行时字符串会错乱。

用法：python3 scripts/check-localization.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOC = ROOT / "Sources" / "Models" / "Localization.swift"

# 词条既可能写成 "key": "value"，也可能 key 和 value 分两行，
# 所以用 DOTALL 让 \s* 能跨行匹配。
ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"', re.S)
CALL = re.compile(r'L\.t\(\s*"((?:[^"\\]|\\.)*)"')
PLACEHOLDER = re.compile(r"%(?![%])[-+ #0]*\d*(?:\.\d+)?[d@uFfgsS]|%%")


def unescape(s: str) -> str:
    return s.replace('\\"', '"').replace("\\\\", "\\")


def placeholders(s: str) -> int:
    return len([m for m in PLACEHOLDER.findall(s) if m != "%%"])


def main() -> int:
    if not LOC.exists():
        print(f"error: 找不到 {LOC}")
        return 1

    lines = LOC.read_text(encoding="utf-8").split("\n")

    # 只解析 english 字典块内部，避免把别处的 "a": "b" 当成词条
    block = "\n".join(lines)
    start = block.find("private static let english")
    end = block.find("\n    ]", start)
    text = block[start:end] if start >= 0 and end > start else block

    # 词条表 key（去重前）
    table: dict[str, int] = {}
    order: list[str] = []
    values: dict[str, str] = {}
    for m in ENTRY.finditer(text):
        key = unescape(m.group(1))
        order.append(key)
        table[key] = table.get(key, 0) + 1
        values[key] = m.group(2)

    errors: list[str] = []
    warnings: list[str] = []

    # 1) 重复 key
    dups = {k: n for k, n in table.items() if n > 1}
    for k, n in sorted(dups.items(), key=lambda kv: -kv[1]):
        errors.append(f"词条重复 {n} 次（会导致运行时 fatalError）：{k!r}")

    # 2) 代码里用到的 key 是否都存在
    used: dict[str, int] = {}
    for path in sorted((ROOT / "Sources").rglob("*.swift")):
        for i, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
            for m in CALL.finditer(line):
                key = unescape(m.group(1))
                used[key] = used.get(key, 0) + 1
                if key not in table:
                    rel = path.relative_to(ROOT)
                    errors.append(f"{rel}:{i} 使用了不存在的词条：{key!r}")

    # 3) 占位符数量
    for key, count in sorted(used.items()):
        if key not in values:
            continue
        en = values[key]
        a, b = placeholders(key), placeholders(en)
        if a != b:
            errors.append(
                f"占位符数量不一致：{key!r} 中文 {a} 个 / 英文 {en!r} {b} 个")

    # 4) 未被使用的词条（提示，不算错）
    unused = [k for k in order if k not in used and not k.startswith("时间,")]
    if unused:
        warnings.append(f"有 {len(unused)} 条词条未被使用（可清理）")

    print(f"词条总数：{len(order)}（唯一 {len(table)}）")
    print(f"代码引用：{len(used)} 个不同 key")

    for w in warnings:
        print(f"warning: {w}")

    if errors:
        print()
        for e in errors:
            print(f"error: {e}")
        print(f"\n共 {len(errors)} 个问题")
        return 1

    print("OK：无重复 key，无缺失词条，占位符一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
