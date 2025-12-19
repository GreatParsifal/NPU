from network_structure import *

if __name__ == "__main__":
    input = load_input("./input_32bit.hex")
    input.reshape(1, 1, 16, 15)

    x = torch.tensor(input, dtype=torch.uint8)

    conv1_res_base = 2000
    conv2_res_base = 4000
    fc1_res_base = 4600
    fc2_res_base = 4700
    
    sram_res = []
    x = quantized_conv2d(x, model.q_conv1_w, model.q_conv1_b)
    x = quantized_relu8(x)

    x = quantized_conv3d(x, model.q_conv2_w, model.q_conv2_b)  # Use 3D convolution
    #print("Shape of x:", x.shape)
    x = quantized_relu8(x)
    x = x.view(x.size(0), -1)  # Flatten for fully connected layers
    #print("Shape of x:", x.shape)
    x = quantized_linear(x, model.q_fc1_w, model.q_fc1_b)
    #print("Shape of x:", x.shape)
    x = quantized_relu8(x)
    x = quantized_linear(x, model.q_fc2_w, model.q_fc2_b)

    file_name = "res.hex"
    with open(file_name, "w") as f:
        for i in range(0, len(sram_res), 4):
            group = sram_res[i:i+4]
            group = group[::-1]  # 逆序
            line = ''.join(group)
            f.write(line + '\n')

    print(f"Calculation finished and d_cache content saved to {file_name}")