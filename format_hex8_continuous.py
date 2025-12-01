import re
from pathlib import Path

def parse_hex_bytes(text: str):
    bytes_out = []
    for line in text.splitlines():
        # 拆分空白分隔的 token（可能是“8位字节”或“32位连写”）
        for tok in line.strip().split():
            # 去掉非十六进制字符
            tok = re.sub(r'[^0-9A-Fa-f]', '', tok)
            if not tok:
                continue
            # 若是奇数个字符，前补 0
            if len(tok) % 2 == 1:
                tok = '0' + tok
            # 按两位切成字节（左到右）
            for i in range(0, len(tok), 2):
                try:
                    b = int(tok[i:i+2], 16)
                    bytes_out.append(b)
                except ValueError:
                    pass
    return bytes_out

def main():
    in_path = Path(r"c:\Users\hutao\MySpace\coding\NPU\dcache_init.hex")
    out_path = in_path.with_name("dcache_init_4bytes_perline.hex")

    text = in_path.read_text(encoding="utf-8", errors="ignore")
    data = parse_hex_bytes(text)

    with out_path.open("w", encoding="utf-8") as f:
        for i in range(0, len(data), 4):
            line = ''.join(f"{b:02X}" for b in data[i:i+4])  # 删掉空格，连续
            f.write(line + "\n")

    print(f"Done. bytes={len(data)}, lines={(len(data)+3)//4}")
    print(f"Output: {out_path}")

if __name__ == "__main__":
    main()