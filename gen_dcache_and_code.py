# 生成:
#  1) dcache_init.hex : FC1/FC2/in_vec 的初始值
#  2) write_npu.S     : CPU 把 dcache 内容搬到 NPU 并触发计算

IN1_N  = 132      # 输入长度
OUT1_M = 10       # FC1/FC2 输出通道数
FC1_BYTES = IN1_N * OUT1_M   # 1320
FC2_BYTES = OUT1_M           # 10
IN_BYTES  = IN1_N            # 132

ACC_BASE  = 0x70000000
DSRAM_BASE = 0x60000000

def gen_hex():
    data_bytes = []

    # FC1: 132 x 10，全 0x01
    for n in range(OUT1_M):
        for k in range(IN1_N):
            data_bytes.append(0x01)

    # FC2: 10 个，全 0x02
    for n in range(OUT1_M):
        data_bytes.append(0x02)

    # in_vec: 132 个，全 0x03
    for k in range(IN1_N):
        data_bytes.append(0x03)

    total_bytes = len(data_bytes)
    assert total_bytes == FC1_BYTES + FC2_BYTES + IN_BYTES

    # 对齐到 4 字节
    pad = (4 - total_bytes % 4) % 4
    data_bytes.extend([0x00] * pad)

    total_words = len(data_bytes) // 4
    print(f"[HEX] total_bytes = {total_bytes}, pad = {pad}, total_words = {total_words}")

    with open("dcache_init.hex", "w") as f:
        for w in range(total_words):
            b0 = data_bytes[4*w + 0]
            b1 = data_bytes[4*w + 1]
            b2 = data_bytes[4*w + 2]
            b3 = data_bytes[4*w + 3]
            # 高字节在前: b3 b2 b1 b0
            word_hex = f"{b3:02X}{b2:02X}{b1:02X}{b0:02X}"
            f.write(word_hex + "\n")

    # 返回每块在 dcache 中的 word 起始/长度，给汇编用
    fc1_words = (FC1_BYTES + 3) // 4
    fc2_off_bytes = FC1_BYTES
    fc2_start_word = (fc2_off_bytes) // 4
    fc2_words = (FC2_BYTES + 3) // 4
    in_off_bytes  = FC1_BYTES + FC2_BYTES
    in_start_word = in_off_bytes // 4
    in_words      = (IN_BYTES + 3) // 4

    return {
        "fc1_start": 0,
        "fc1_words": fc1_words,
        "fc2_start": fc2_start_word,
        "fc2_words": fc2_words,
        "in_start":  in_start_word,
        "in_words":  in_words,
        "total_words": total_words,
    }

def gen_asm(layout):
    fc1_start = layout["fc1_start"]
    fc1_words = layout["fc1_words"]
    fc2_start = layout["fc2_start"]
    fc2_words = layout["fc2_words"]
    in_start  = layout["in_start"]
    in_words  = layout["in_words"]

    with open("write_npu.S", "w") as f:
        f.write("""\
    .section .text
    .globl _boot
_boot:
    # t0 = ACC_BASE (NPU)
    lui   t0, %hi({acc_base:#x})
    addi  t0, t0, %lo({acc_base:#x})
    # t1 = DSRAM_BASE
    lui   t1, %hi({ds_base:#x})
    addi  t1, t1, %lo({ds_base:#x})

    # -------------------------------
    # 搬运 FC1: {fc1_words} word，从 dcache[{fc1_start}] 开始 -> NPU sel=3 (011)
    li    t2, {fc1_start}         # w = fc1_start
1:  bge   t2, {fc1_end}, 2f       # if w >= fc1_end -> break
    slli  t3, t2, 2               # t3 = w*4
    add   t4, t1, t3              # t4 = DSRAM_BASE + w*4
    lw    t5, 0(t4)               # t5 = dcache[w]

    # 计算 NPU 地址: sel=3, idx = (t2 - fc1_start)
    li    t6, (3 << 12)           # t6 = sel<<12
    addi  t6, t6, 0               # 占位，方便看
    addi  t3, t2, -{fc1_start}    # t3 = idx = w - fc1_start
    slli  t3, t3, 2               # idx<<2
    or    t3, t3, t6              # (sel<<12 | idx)<<2
    slli  t3, t3, 2               # 再 <<2
    add   t3, t0, t3              # t3 = NPU addr
    sw    t5, 0(t3)

    addi  t2, t2, 1
    j     1b
2:

    # -------------------------------
    # 搬运 FC2: {fc2_words} word，从 dcache[{fc2_start}] 开始 -> NPU sel=4 (100)
    li    t2, {fc2_start}
3:  bge   t2, {fc2_end}, 4f
    slli  t3, t2, 2
    add   t4, t1, t3
    lw    t5, 0(t4)

    li    t6, (4 << 12)           # sel=4
    addi  t3, t2, -{fc2_start}    # idx = w - fc2_start
    slli  t3, t3, 2
    or    t3, t3, t6
    slli  t3, t3, 2
    add   t3, t0, t3
    sw    t5, 0(t3)

    addi  t2, t2, 1
    j     3b
4:

    # -------------------------------
    # 搬运 in_vec: {in_words} word，从 dcache[{in_start}] 开始 -> NPU sel=0 (000)
    li    t2, {in_start}
5:  bge   t2, {in_end}, 6f
    slli  t3, t2, 2
    add   t4, t1, t3
    lw    t5, 0(t4)

    li    t6, (0 << 12)           # sel=0
    addi  t3, t2, -{in_start}     # idx = w - in_start
    slli  t3, t3, 2
    or    t3, t3, t6
    slli  t3, t3, 2
    add   t3, t0, t3
    sw    t5, 0(t3)

    addi  t2, t2, 1
    j     5b
6:

    # -------------------------------
    # 启动 NPU: 写 1 到 sel=5, idx=1
    li    t6, (5 << 12)
    li    t3, 1                   # idx=1
    slli  t3, t3, 2
    or    t3, t3, t6
    slli  t3, t3, 2
    add   t3, t0, t3
    li    t5, 1
    sw    t5, 0(t3)

    # -------------------------------
    # 轮询 done: sel=5, idx=0
poll_done:
    li    t6, (5 << 12)
    li    t3, 0                   # idx=0
    slli  t3, t3, 2
    or    t3, t3, t6
    slli  t3, t3, 2
    add   t3, t0, t3
    lw    t5, 0(t3)
    andi  t5, t5, 1
    beqz  t5, poll_done

    # -------------------------------
    # 读 result: sel=5, idx=1
    li    t6, (5 << 12)
    li    t3, 1
    slli  t3, t3, 2
    or    t3, t3, t6
    slli  t3, t3, 2
    add   t3, t0, t3
    lw    a0, 0(t3)               # a0 = 结果

stop:
    j     stop
""".format(
            acc_base=ACC_BASE,
            ds_base=DSRAM_BASE,
            fc1_start=fc1_start,
            fc1_end=fc1_start + fc1_words,
            fc1_words=fc1_words,
            fc1_words_minus1=fc1_words - 1,
            fc2_start=fc2_start,
            fc2_end=fc2_start + fc2_words,
            fc2_words=fc2_words,
            in_start=in_start,
            in_end=in_start + in_words,
            in_words=in_words,
        ))

    print("[ASM] write_npu.S generated")

def main():
    layout = gen_hex()
    gen_asm(layout)

if __name__ == "__main__":
    main()