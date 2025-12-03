module conv2_tb;
    // 参数 (与被测模块保持一致)
    parameter K_H = 3;
    parameter K_W = 3;
    parameter MAX_H = 16;
    parameter MAX_W = 15;
    parameter DATA_WIDTH = 8;

    // 信号
    reg clk;
    reg rst_n;
    reg trigger;
    reg save_done;
    reg [4:0] in_w;
    reg [4:0] in_h;
    reg layer;

    // 输入/权重缓冲（testbench 提供）
    reg [DATA_WIDTH-1:0] in_img [0 : MAX_H * MAX_W - 1];
    reg signed [DATA_WIDTH-1:0] w_conv_tb [K_H][K_W];

    // DUT 输出
    wire valid;
    wire signed [23:0] out_pixel_full;

    wire [7:0] addr;
    reg [7:0] cnt;

    // 实例化 DUT（端口名与模块一致）
    reg clear_conv;

    conv u_conv (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear_conv),
        .trigger(trigger),
        .save_done(save_done),
        .layer(layer),
        .in_img(in_img),
        .w_conv(w_conv_tb),
        .valid(valid),
        .out_pixel(out_pixel_full),
        .addr(addr)
    );

    
    wire signed [23:0] out_data_full [12][11];
    reg clear_sum;
    wire valid_sum;
    partial_sum u_sum (
        .clk(clk),
        .ce(layer),
        .rst_n(rst_n),
        .clear(clear_sum),
        .addr(addr),
        .in_data(out_pixel_full),
        .in_valid(valid),
        .out_data(out_data_full),
        .out_valid(valid_sum)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns 周期
    end

    integer i, j, ii, jj, c;
    integer out_w, out_h;
    integer row, col;
    integer cycles;
    reg signed [31:0] acc[12][11];
    wire signed [23:0] expected[12][11];
    reg detected_done;

    genvar gi, gj;
    for (gi=0;gi<12;gi=gi+1) begin
        for (gj=0;gj<11;gj=gj+1) begin
            assign expected[gi][gj] = acc[gi][gj][23:0];
        end
    end

    initial begin
        // 1. 初始赋值
        clk = 0;
        rst_n = 0;
        clear_conv = 1;
        clear_sum = 1;
        trigger = 0;
        save_done = 0;
        in_w = 13;
        in_h = 14;
        cnt = 0;
        layer = 1'b1; // 测试 conv1 (layer=0)；需要时可改成 1 测试 conv2
        detected_done = 0;
        for (i=0;i<12;i=i+1) begin
            for (j=0;j<11;j=j+1) begin
                acc[i][j] = 0;
            end
        end

        // 2. rst_n 低一段时间复位
        #20;
        rst_n = 0;
        clear_conv = 1;
        clear_sum = 1;
        #20;
        rst_n = 1;
        clear_conv = 0;
        clear_sum = 0;
        #20;

        for (c = 0; c < 10; c = c + 1) begin // channel loop
            // 填充输入图像（可替换为其它模式或随机）
            for (i = 0; i < MAX_H; i = i + 1) begin
                for (j = 0; j < MAX_W; j = j + 1) begin
                    in_img[i*in_w + j] = i * in_w + j; // 可读的序列值
                    // in_img[i*in_w + j] = $random(); // 可读的序列值
                end
            end

            // 填充权重 (示例小整数)
            for (ii = 0; ii < K_H; ii = ii + 1) begin
                for (jj = 0; jj < K_W; jj = jj + 1) begin
                    w_conv_tb[ii][jj] = (ii - 1) + (jj - 1); // e.g. -2..2
                end
            end

            // 3. 产生一个 trigger 上升沿脉冲，开始计算
            @(posedge clk);
            trigger = 1;
            @(posedge clk);
            trigger = 0;

            // 计算输出尺寸
            out_h = in_h - K_H + 1;
            out_w = in_w - K_W + 1;

            // 4. 监测 valid，校验 out_pixel_full 与 addr 对应位置的真实值
            cycles = 0;
            while (!detected_done && cycles < 200000) begin
                @(posedge clk);
                cycles = cycles + 1;

                if (valid_sum) begin
                    // addr mapping -> row, col
                    row = addr / out_w;
                    col = addr % out_w;

                    // 计算期望值（与 conv 模块内部 conv_unit 行为一致）
                    for (ii = 0; ii < K_H; ii = ii + 1) begin
                        for (jj = 0; jj < K_W; jj = jj + 1) begin
                            // in_img 无符号扩展为 1'b0 + DATA_WIDTH bits，然后与 signed weight 相乘
                            acc[row][col] += $signed({1'b0, in_img[(row + ii)*in_w + (col + jj)]}) * $signed(w_conv_tb[ii][jj]);
                        end
                    end

                    if (out_data_full[row][col] !== expected[row][col]) begin
                        $display("ERROR: addr=%0d, chan=%0d -> (row=%0d,col=%0d) DUT=%0d EXPECT=%0d at time %0t", addr, c, row, col, out_data_full[row][col], expected[row][col], $time);
                    end else begin
                        $display("OK: addr=%0d, chan=%0d -> (row=%0d,col=%0d) value=%0d at time %0t", addr, c, row, col, out_data_full[row][col], $time);
                    end
                    if (addr == out_w * out_h - 1) begin
                        detected_done = 1;
                        $display("Finished calculation for channel %0d at time %0t", c, $time);
                        // 5. 检测到 done 后等待 10 周期再结束仿真
                        clear_conv = 1;
                        repeat (10) @(posedge clk);
                        clear_conv = 0;
                        #10;
                    end else begin
                        // 等待 3 个周期后给 save_done 一个脉冲（通知 DUT 已保存/消费该像素）
                        repeat (3) @(posedge clk);
                        save_done = 1;
                        cnt += 1;
                        @(posedge clk);
                        save_done = 0;
                    end
                end
            end

            if (cycles >= 200000) begin
                $display("Timeout waiting for DUT finish, chan=%0d", c);
                $finish;
            end else begin 
                detected_done = 0;
            end
        end // channel loop
        $display("All channels done, finishing simulation at time %0t", $time);
        #50;
        $finish;
    end

    // waveform dump (可选)
    initial begin
        $fsdbDumpfile("conv2_tb.fsdb");
        $fsdbDumpvars(0, conv2_tb);
        $fsdbDumpMDA();
    end

endmodule