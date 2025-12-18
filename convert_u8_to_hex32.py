"""
把嵌套的 uint8 数组文本（如 [[[...]]] 或任意空白/逗号分隔的数字）
转换为：每行 4 个 8-bit 数，按小端（第一个数为低位）拼成 32-bit，
输出为 8 个十六进制字符一行。默认输出 28 行（不足补 0，多余裁剪）。

用法：
  python convert_u8_to_hex32.py -i input.hex -o output.hex --lines 28
"""

from __future__ import annotations
import argparse
import re
from pathlib import Path
from typing import List, Optional


def parse_u8_numbers(text: str) -> List[int]:
    """从文本中提取所有十进制数字，限制到 0..255。"""
    nums: List[int] = []
    for tok in re.findall(r"[-+]?\d+", text):
        try:
            v = int(tok)
        except ValueError:
            continue
        # 允许负数？若出现，按 uint8 处理
        if v < 0:
            v = v % 256
        if 0 <= v <= 255:
            nums.append(v)
    return nums


def to_hex32_lines(u8s: List[int], lines: Optional[int]) -> List[str]:
    """将 u8 序列转为 32-bit 小端 hex 行。
    - 若 lines 为 None：输出覆盖所有输入（按 4 字节一组），末尾不足 4 字节用 0 补齐；
    - 若 lines 为整数：输出固定行数，不足补 0，多余裁剪。
    """
    if lines is None:
        # 需要的总字节向上取整到 4 的倍数
        needed = ((len(u8s) + 3) // 4) * 4
        data = u8s[:needed]
        if len(data) < needed:
            data = data + [0] * (needed - len(data))
    else:
        needed = lines * 4
        data = u8s[:needed]
        if len(data) < needed:
            data = data + [0] * (needed - len(data))

    out: List[str] = []
    for i in range(0, needed, 4):
        b0, b1, b2, b3 = data[i : i + 4]
        # 小端：第一个数放低位 -> 输出字节顺序 b3 b2 b1 b0
        out.append(f"{b3:02X}{b2:02X}{b1:02X}{b0:02X}")
    return out


def main():
    ap = argparse.ArgumentParser(description="将 uint8 序列转换为每行 4 字节的小端 32-bit HEX")
    ap.add_argument("-i", "--input", type=Path, required=True, help="输入包含 uint8 的文本文件")
    ap.add_argument("-o", "--output", type=Path, required=True, help="输出 HEX 文件（8 十六进制/行）")
    ap.add_argument("--lines", type=int, default=None, help="限制输出行数；不提供则输出所有分组")
    args = ap.parse_args()

    text = args.input.read_text(encoding="utf-8", errors="ignore")
    nums = parse_u8_numbers(text)

    lines = to_hex32_lines(nums, args.lines)

    with args.output.open("w", encoding="utf-8") as f:
        for ln in lines:
            f.write(ln + "\n")

    print(f"Parsed u8 count: {len(nums)}")
    print(f"Wrote lines: {len(lines)} -> {args.output}")


if __name__ == "__main__":
    main()
