from network_structure import *

if __name__ == "__main__":

    hex_list = []
    for chan in range(10):
        for row in range(3):
            for col in range(3):
                val = conv1_weight[chan, 0, col, row]
                # np.int8转无符号8位整数
                val = int(val) & 0xFF
                hex_str = format(val, '02X')
                hex_list.append(hex_str)
    for chan in range(10):
        for row in range(3):
            for col in range(3):
                val = conv2_weight[0, chan, col, row]
                # np.int8转无符号8位整数
                val = int(val) & 0xFF
                hex_str = format(val, '02X')
                hex_list.append(hex_str)
    for chan in range(3):                     ### fc1 1-9 chan
        for row in range(132):
            for i in range(3):
                val = fc1_weight[chan*3+i, row]
                # np.int8转无符号8位整数
                val = int(val) & 0xFF
                hex_str = format(val, '02X')
                hex_list.append(hex_str)
    for row in range(132):                  ## fc1 last chan
        val = fc1_weight[9, row]
        # np.int8转无符号8位整数
        val = int(val) & 0xFF
        hex_str = format(val, '02X')
        hex_list.append(hex_str)
    for row in range(10):
        val = fc2_weight[0, row]
        # np.int8转无符号8位整数
        val = int(val) & 0xFF
        hex_str = format(val, '02X')
        hex_list.append(hex_str)
    # print(hex_list)

    with open("weights.hex", "w") as f:
        for i in range(0, len(hex_list), 4):
            group = hex_list[i:i+4]
            group = group[::-1]  # 逆序
            line = ''.join(group)
            f.write(line + '\n')
    
