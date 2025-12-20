if __name__ == "__main__":
    with open("./res.hex", "r") as f:
        golden = f.read().splitlines()
    with open("../dcache.hex", "r") as f:
        res = f.read().splitlines()

    # check conv1 result
    conv1_golden = golden[:455]
    print(conv1_golden[0])
    conv1_res = res[500:500+455]
    print(conv1_res[0])
    err_addr = -1
    for i in range(455):
        if (conv1_golden[i].upper() != conv1_res[i].upper()):
            err_addr = i
            break
    if err_addr == -1:
        print("conv1 result all right!")
    else:
        print(f"find error in addr range {err_addr*4} - {err_addr*4+3}")
    
    # check conv2 result
    conv2_golden = golden[500:500+33]
    print(conv2_golden[0])
    conv2_res = res[1000:1000+33]
    print(conv2_res[0])
    err_addr = -1
    for i in range(33):
        if (conv2_golden[i].upper() != conv2_res[i].upper()):
            err_addr = i
            break
    if err_addr == -1:
        print("conv1 result all right!")
    else:
        print(f"find error in addr range {err_addr*4} - {err_addr*4+3}")