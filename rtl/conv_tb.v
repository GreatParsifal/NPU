// ...existing code...
module conv_tb;

    // parameters must match conv.v (可以调整 CHAN 以加快仿真)
    localparam K_H = 3;
    localparam K_W = 3;
    localparam IN1_H = 16;
    localparam IN1_W = 15;
    localparam OUT1_H = 14;
    localparam OUT1_W = 13;
    localparam OUT2_H = 12;
    localparam OUT2_W = 11;
    localparam CHAN = 4; // 为仿真方便使用 4 个通道，实际可设为 10

    // DUT interface
    reg clk;
    reg rst_n;
    reg trigger;

    // inputs
    reg [7:0] in_img [0:IN1_H-1][0:IN1_W-1];
    reg signed [7:0] w_conv1 [0:K_H-1][0:K_W-1][0:CHAN-1];
    reg signed [7:0] w_conv2 [0:K_H-1][0:K_W-1][0:CHAN-1];

    // outputs from DUT
    wire signed [23:0] out_buff [0:OUT2_H-1][0:OUT2_W-1];
    wire out_valid;
    wire [3:0] out_chan;

    // instantiate DUT (覆盖 CHAN 以匹配本 tb)
    conv #(
        .K_H(K_H),
        .K_W(K_W),
        .IN1_H(IN1_H),
        .IN1_W(IN1_W),
        .OUT1_H(OUT1_H),
        .OUT1_W(OUT1_W),
        .OUT2_H(OUT2_H),
        .OUT2_W(OUT2_W),
        .CHAN(CHAN)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .trigger(trigger),
        .in_img(in_img),
        .w_conv1(w_conv1),
        .w_conv2(w_conv2),
        .out_buff(out_buff),
        .out_valid(out_valid),
        .out_chan(out_chan)
    );

    // for golden model
    integer r, c, ky, kx, ch;
    reg signed [31:0] acc1;
    reg signed [31:0] acc2;
    // conv1 输出为 24-bit 的 conv + ReLU（无 INT8 量化），在 golden 中以 signed [23:0] 表示
    reg signed [23:0] conv1_out_map [0:OUT1_H-1][0:OUT1_W-1]; // conv1 的最终 24-bit 输出（ReLU 后）
    reg signed [31:0] conv1_full_acc [0:OUT1_H-1][0:OUT1_W-1]; // 用于保存 full-precision 累加结果（临时）
    reg signed [23:0] golden [0:OUT2_H-1][0:OUT2_W-1];

    integer errors;
    integer seed;

    // clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    // test sequence
    initial begin

        seed = 32'hDEADBEEF;
        // 初始化随机输入与权重（可改为固定向量以便调试）
        for (r = 0; r < IN1_H; r = r + 1) begin
            for (c = 0; c < IN1_W; c = c + 1) begin
                in_img[r][c] = $urandom_range(0, 255);
            end
        end
        for (ky = 0; ky < K_H; ky = ky + 1) begin
            for (kx = 0; kx < K_W; kx = kx + 1) begin
                for (ch = 0; ch < CHAN; ch = ch + 1) begin
                    w_conv1[ky][kx][ch] = $urandom_range(-128, 127);
                    w_conv2[ky][kx][ch] = $urandom_range(-128, 127);
                end
            end
        end

        // reset
        rst_n = 0;
        trigger = 0;
        #20;
        rst_n = 1;
        #10;

        // 产生一个上升沿 trigger 开始计算（与 conv 模块约定）
        @(posedge clk);
        trigger = 1;
        @(posedge clk);
        trigger = 0;

        // 对每个 channel 计算 golden 值并等待 DUT 的 out_valid/assert
        errors = 0;
        for (ch = 0; ch < CHAN; ch = ch + 1) begin
            // step1: conv1 full precision accumulation -> conv1 的 24-bit 输出，并做 ReLU（非负）
            for (r = 0; r < OUT1_H; r = r + 1) begin
                for (c = 0; c < OUT1_W; c = c + 1) begin
                    acc1 = 0;
                    for (ky = 0; ky < K_H; ky = ky + 1) begin
                        for (kx = 0; kx < K_W; kx = kx + 1) begin
                            // in_img 是 0..255 (unsigned)，按 conv1 中实现将其视为非负数
                            acc1 = acc1 + $signed({1'b0, in_img[r + ky][c + kx]}) * $signed(w_conv1[ky][kx][ch]);
                        end
                    end
                    conv1_full_acc[r][c] = acc1;
                    // conv1 输出为 conv + ReLU，保留 24 位（如果累加超出 24 位则截断低 24 位）
                    if (acc1 < 0) conv1_out_map[r][c] = 0;
                    else conv1_out_map[r][c] = acc1[23:0];
                end
            end

            // step2: conv2 使用 conv1_out_map 作为输入进行卷积，得到 golden final map
            for (r = 0; r < OUT2_H; r = r + 1) begin
                for (c = 0; c < OUT2_W; c = c + 1) begin
                    acc2 = 0;
                    for (ky = 0; ky < K_H; ky = ky + 1) begin
                        for (kx = 0; kx < K_W; kx = kx + 1) begin
                            // conv1_out_map 为 signed [23:0]（非负），与 signed weight 相乘
                            acc2 = acc2 + $signed(conv1_out_map[r + ky][c + kx]) * $signed(w_conv2[ky][kx][ch]);
                        end
                    end
                    golden[r][c] = acc2[23:0]; // 截断到 24 位，与 DUT 输出类型一致
                end
            end

            // wait DUT produce out_valid for this channel
            // conv module 在完成一个通道后会把 out_valid 拉高且 out_chan 指示当前通道
            // 等待并检查
            wait_for_channel_and_check: begin
                // 等待 out_valid for this channel (加超时避免无限等待)
                integer timeout;
                timeout = 10000;
                forever begin
                    @(posedge clk);
                    if (out_valid && out_chan == ch) begin
                        // compare DUT out_buff 与 golden
                        for (r = 0; r < OUT2_H; r = r + 1) begin
                            for (c = 0; c < OUT2_W; c = c + 1) begin
                                if (out_buff[r][c] !== golden[r][c]) begin
                                    $display("ERROR: ch=%0d, pixel(%0d,%0d): DUT=%0d GOLD=%0d", ch, r, c, out_buff[r][c], golden[r][c]);
                                    errors = errors + 1;
                                end
                            end
                        end
                        // consume the out_valid edge and leave loop
                        disable wait_for_channel_and_check;
                    end
                    timeout = timeout - 1;
                    if (timeout == 0) begin
                        $display("TIMEOUT waiting for out_valid for channel %0d", ch);
                        errors = errors + 1;
                        disable wait_for_channel_and_check;
                    end
                end
            end
            // small spacing before检测下一个 channel
            #10;
        end

        if (errors == 0) $display("ALL CHANNELS PASSED");
        else $display("FAILED: %0d mismatches", errors);

        #20;
        $finish;
    end

    initial begin
        $fsdbDumpfile("conv_tb.fsdb");
        $fsdbDumpvars(0, conv_tb);
        $fsdbDumpMDA();
    end

endmodule
// ...existing code...