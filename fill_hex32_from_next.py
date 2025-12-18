"""
将每行十六进制字符串补齐为 32-bit（8 个十六进制字符）。

规则：
- 若某行长度 < 8，则从下一行的“低位”（右端）借位补齐到当前行的高位；
- 即“借来的数字在高位，原来的数保留在低位”；
- 若下一行也不够，则继续从再下一行借，依此类推；
- 被借走的低位会从对应行中删除；
- 若到文件末尾仍不足 8，则在该行高位补 0；
- 输入中若某行长度 > 8，则会按从左到右拆分为多条 8 字符行（尽量保留信息）。

示例：
    行 i   : 0EF4        （4 个字符）
    行 i+1 : ECFDE915    （8 个字符）
    结果行 i: E9150EF4   （从下一行右侧借 4 个字符放到高位）
    新的行 i+1: ECFD

用法：
  python fill_hex32_from_next.py -i dcache_init_4bytes_perline.hex -o dcache_init_32bit_filled.hex
"""

from __future__ import annotations
import argparse
import re
from pathlib import Path
from typing import List


HEX_RE = re.compile(r"[0-9A-Fa-f]+")


def normalize_hex(s: str) -> str:
    """提取十六进制字符并转为大写，若为奇数字符则左侧补 0。"""
    m = HEX_RE.findall(s)
    if not m:
        return ""
    tok = "".join(m).upper()
    if len(tok) % 2 == 1:
        tok = "0" + tok
    return tok


def split_overflow(line: str) -> List[str]:
    """若某行长度 > 8，则按 8 字符一组从左到右拆分为多行。"""
    if len(line) <= 8:
        return [line]
    out = []
    i = 0
    while i < len(line):
        out.append(line[i : i + 8])
        i += 8
    return out


def fill_to_32bit(lines: List[str]) -> List[str]:
    """
    主逻辑：对每一行补齐到 8 个十六进制字符，借位来自下一行（右端）。
    会就地消费后续行的低位字符；若最后仍不足，则在当前行右侧补 0。
    """
    # 先把每行都处理成不超过 8 字符（>8 的分拆为多行，尽量不丢信息）
    normalized: List[str] = []
    for s in lines:
        if not s:
            continue
        for chunk in split_overflow(s):
            normalized.append(chunk)

    i = 0
    while i < len(normalized):
        cur = normalized[i]
        if len(cur) == 8:
            i += 1
            continue

        # 借位填充（借来的数字应放到高位，原行在低位）
        need = 8 - len(cur)
        j = i + 1
        while need > 0 and j < len(normalized):
            nxt = normalized[j]
            if not nxt:
                # 删除空行
                normalized.pop(j)
                continue
            take = min(need, len(nxt))
            # 从下一行的右端（低位）截取 take 个字符，放到当前行高位
            cur = nxt[-take:] + cur
            nxt = nxt[: len(nxt) - take]
            normalized[i] = cur
            if nxt:
                normalized[j] = nxt
            else:
                normalized.pop(j)  # 删除已被取空的行
            need = 8 - len(cur)

        # 文件末尾仍不足，高位补 0
        if len(cur) < 8:
            cur = ("0" * (8 - len(cur))) + cur
            normalized[i] = cur

        i += 1

    return normalized


def main():
    ap = argparse.ArgumentParser(description="按低位借位补齐到 32-bit 的 HEX 行处理器")
    ap.add_argument("-i", "--input", type=Path, required=True, help="输入 hex 文件路径")
    ap.add_argument(
        "-o", "--output", type=Path, required=False, help="输出文件路径（默认同目录 *_filled.hex）"
    )
    args = ap.parse_args()

    text = args.input.read_text(encoding="utf-8", errors="ignore")
    raw_lines = [normalize_hex(ln) for ln in text.splitlines()]
    # 过滤空行
    raw_lines = [ln for ln in raw_lines if ln]

    filled = fill_to_32bit(raw_lines)

    out_path = args.output or args.input.with_name(args.input.stem + "_filled.hex")
    with out_path.open("w", encoding="utf-8") as f:
        for ln in filled:
            f.write(ln.upper() + "\n")

    print(f"Input lines: {len(raw_lines)}")
    print(f"Output lines: {len(filled)}")
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    main()
