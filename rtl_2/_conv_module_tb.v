module conv_tb;
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
    reg [3:0] chan;
    reg layer;

    // 输入/权重缓冲（testbench 提供）
    reg [DATA_WIDTH-1:0] in_img [0:MAX_H-1][0:MAX_W-1];
    reg signed [DATA_WIDTH-1:0] w_conv_tb [0:K_H-1][0:K_W-1];

    // DUT 输出
    wire valid;
    wire done;
    wire signed [DATA_WIDTH-1:0] out_pixel;
    wire [7:0] addr;

    // 实例化 DUT（端口名与模块一致）
    conv dut (
        .clk(clk),
        .rst_n(rst_n),
        .trigger(trigger),
        .save_done(save_done),
        .in_w(in_w),
        .in_h(in_h),
        .chan(chan),
        .layer(layer),
        .in_img(in_img),
        .w_conv(w_conv_tb),
        .valid(valid),
        .done(done),
        .out_pixel(out_pixel),
        .addr(addr)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns 周期
    end

    integer i, j, ii, jj;
    integer out_w, out_h;
    integer row, col;
    integer cycles;
    reg signed [31:0] acc;
    reg signed [DATA_WIDTH-1:0] expected;
    reg detected_done;

    initial begin
        // 1. 初始赋值
        clk = 0;
        rst_n = 0;
        trigger = 0;
        save_done = 0;
        in_w = MAX_W; // 15
        in_h = MAX_H; // 16
        chan = 4'd0;
        layer = 1'b0; // 测试 conv1 (layer=0)；需要时可改成 1 测试 conv2
        detected_done = 0;

        // 填充输入图像（可替换为其它模式或随机）
        for (i = 0; i < MAX_H; i = i + 1) begin
            for (j = 0; j < MAX_W; j = j + 1) begin
                in_img[i][j] = i * MAX_W + j; // 可读的序列值
            end
        end

        // 填充权重 (示例小整数)
        for (ii = 0; ii < K_H; ii = ii + 1) begin
            for (jj = 0; jj < K_W; jj = jj + 1) begin
                w_conv_tb[ii][jj] = (ii - 1) + (jj - 1); // e.g. -2..2
            end
        end

        // 2. rst_n 低一段时间复位
        #20;
        rst_n = 0;
        #20;
        rst_n = 1;
        #20;

        // 3. 产生一个 trigger 上升沿脉冲，开始计算
        @(posedge clk);
        trigger = 1;
        @(posedge clk);
        trigger = 0;

        // 计算输出尺寸
        out_h = in_h - K_H + 1;
        out_w = in_w - K_W + 1;

        // 4. 监测 valid / done，校验 out_pixel 与 addr 对应位置的真实值
        cycles = 0;
        while (!detected_done && cycles < 200000) begin
            @(posedge clk);
            cycles = cycles + 1;

            if (valid || done) begin
                // addr mapping -> row, col
                row = addr / out_w;
                col = addr % out_w;

                // 计算期望值（与 conv 模块内部 conv_unit 行为一致）
                acc = 0;
                for (ii = 0; ii < K_H; ii = ii + 1) begin
                    for (jj = 0; jj < K_W; jj = jj + 1) begin
                        // in_img 无符号扩展为 1'b0 + DATA_WIDTH bits，然后与 signed weight 相乘
                        acc = acc + $signed({1'b0, in_img[row + ii][col + jj]}) * $signed(w_conv_tb[ii][jj]);
                    end
                end
                // 若 layer==0 则 en_relu = ~layer = 1 -> ReLU 有效（负值置 0）
                if (~|layer && acc < 0) begin
                    expected = {DATA_WIDTH{1'b0}};
                end else begin
                    // 截断为 DATA_WIDTH 位（低位截断）
                    expected = acc[DATA_WIDTH-1:0];
                end

                if (out_pixel !== expected) begin
                    $display("ERROR: addr=%0d -> (row=%0d,col=%0d) DUT=%0d EXPECT=%0d at time %0t", addr, row, col, out_pixel, expected, $time);
                end else begin
                    $display("OK: addr=%0d -> (row=%0d,col=%0d) value=%0d at time %0t", addr, row, col, out_pixel, $time);
                end
                if (done) begin
                    detected_done = 1;
                    $display("Detected DONE at time %0t", $time);
                    // 5. 检测到 done 后等待 10 周期再结束仿真
                    repeat (10) @(posedge clk);
                    $display("Testbench finished after DONE.");
                    #10;
                    $finish;
                end else begin
                    // 等待 3 个周期后给 save_done 一个脉冲（通知 DUT 已保存/消费该像素）
                    repeat (3) @(posedge clk);
                    save_done = 1;
                    @(posedge clk);
                    save_done = 0;
                end
            end
        end

        if (cycles >= 200000) begin
            $display("Timeout waiting for DUT finish");
            $finish;
        end
    end

    // waveform dump (可选)
    initial begin
        $fsdbDumpfile("conv_module_tb.fsdb");
        $fsdbDumpvars(0, conv_tb);
        $fsdbDumpMDA();
    end

endmodule