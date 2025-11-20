# gen_dcache_hex.py
# 生成 dcache_init.hex:
# - FC1 weights: 132 x 10 = 1320 bytes (all 0x01)
# - FC2 weights: 10 bytes (all 0x02)
# - input vector: 132 bytes (all 0x03)
# - 打包成 32-bit word，每行 8 个 hex 字符，高字节在前

IN1_N = 132      # 输入长度
OUT1_M = 10      # FC1/FC2 输出通道数
FC1_BYTES = IN1_N * OUT1_M   # 1320
FC2_BYTES = OUT1_M           # 10
IN_BYTES  = IN1_N            # 132

def main():
    data_bytes = []

    # FC1: neuron-major 展平，idx = n * IN1_N + k -> 全 0x01
    for n in range(OUT1_M):
        for k in range(IN1_N):
            data_bytes.append(0x01)

    # FC2: 10 个 -> 全 0x02
    for n in range(OUT1_M):
        data_bytes.append(0x02)

    # input vector: 132 个 -> 全 0x03
    for k in range(IN1_N):
        data_bytes.append(0x03)

    total_bytes = len(data_bytes)
    assert total_bytes == FC1_BYTES + FC2_BYTES + IN_BYTES

    if total_bytes % 4 != 0:
        pad = 4 - (total_bytes % 4)
        data_bytes.extend([0x00] * pad)
    else:
        pad = 0

    total_words = len(data_bytes) // 4
    print(f"total_bytes = {total_bytes}, pad = {pad}, total_words = {total_words}")

    with open("dcache_init.hex", "w") as f:
        for w in range(total_words):
            b0 = data_bytes[4*w + 0]
            b1 = data_bytes[4*w + 1]
            b2 = data_bytes[4*w + 2]
            b3 = data_bytes[4*w + 3]
            word_hex = f"{b3:02X}{b2:02X}{b1:02X}{b0:02X}"
            f.write(word_hex + "\n")

if __name__ == "__main__":
    main()