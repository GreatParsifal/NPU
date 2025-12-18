from network_structure import *

if __name__ == "__main__":
    print(conv1_weight.shape)
    s = conv1_weight.shape

    hex_list = []
    for chan in range(s[0]):
        for row in range(s[2]):
            for col in range(s[3]):
                val = conv1_weight[chan, 0, row, col]
                # np.int8转无符号8位整数
                val = int(val) & 0xFF
                hex_str = format(val, '02X')
                hex_list.append(hex_str)
    for chan in range(s[1]):
        for row in range(s[2]):
            for col in range(s[3]):
                val = conv2_weight[0, chan, row, col]
                # np.int8转无符号8位整数
                val = int(val) & 0xFF
                hex_str = format(val, '02X')
                hex_list.append(hex_str)
    print(hex_list)
