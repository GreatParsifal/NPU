from network_structure import *

if __name__ == "__main__":
    input = load_input("./input_32bit.hex")
    input = input.reshape(1, 1, 16, 15)
    print(input)
    for i in range(3):
        for j in range(3):
            print(input[0, 0, 1+i, 5+j], end=' ')
        print()

    x = torch.tensor(input, dtype=torch.uint8)

    conv1_res_base = 2000
    conv2_res_base = 4000
    fc1_res_base = 4600
    fc2_res_base = 4700
    
    sram_res = []
    # conv1
    x = quantized_conv2d(x, model.q_conv1_w, model.q_conv1_b)
    # x = quantized_relu8(x)
    print("Shape of x:", x.shape)
    print(x)
    _, chan, col, row = x.shape
    for ch in range(chan):
        for c in range(col):
            for r in range(row):
                val = x[0, ch, c, r]
                val = int(val) & 0xFF
                str = format(val, '02X')
                sram_res.append(str)
    for i in range(4000-2000-1820):
        sram_res.append('xx')
    # conv2
    x = quantized_conv3d(x, model.q_conv2_w, model.q_conv2_b)  # Use 3D convolution
    print("Shape of x:", x.shape)
    # x = quantized_relu8(x)
    chan, _, col, row = x.shape
    for ch in range(chan):
        for c in range(col):
            for r in range(row):
                val = x[ch, 0, c, r]
                val = int(val) & 0xFF
                str = format(val, '02X')
                sram_res.append(str)
    for i in range(4600-4000-132*4):
        sram_res.append('xx')
    # fcn1
    x = x.view(x.size(0), -1)  # Flatten for fully connected layers
    print("Shape of x:", x.shape)
    x = quantized_linear(x, model.q_fc1_w, model.q_fc1_b)
    print("Shape of x:", x.shape)
    # x = quantized_relu8(x)
    chan, row = x.shape
    for ch in range(chan):
        for r in range(row):
            val = x[ch, r]
            val = int(val) & 0xFF
            str = format(val, '02X')
            sram_res.append(str)
    for i in range(4700-4600-10):
        sram_res.append('xx')

    # fcn2
    x = quantized_linear(x, model.q_fc2_w, model.q_fc2_b)
    print("Shape of x:", x.shape)
    val = x[0, 0]
    val = int(val) & 0xFF
    str = format(val, '02X')
    sram_res.append(str)

    file_name = "res.hex"
    with open(file_name, "w") as f:
        for i in range(0, len(sram_res), 4):
            group = sram_res[i:i+4]
            group = group[::-1]  # 逆序
            line = ''.join(group)
            f.write(line + '\n')

    print(f"Calculation finished and d_cache content saved to {file_name}")