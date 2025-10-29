// verilog
`timescale 1ns/1ps

module tb_conv1;
    // parameters must match conv1
    parameter K_H = 3;
    parameter K_W = 3;
    parameter IN1_H = 16;
    parameter IN1_W = 15;
    parameter OUT1_H = 14;
    parameter OUT1_W = 13;
    parameter CHAN = 10;
    localparam TOTAL = OUT1_H * OUT1_W * CHAN;

    // signals
    reg clk;
    reg rst_n;
    reg trigger;

    // flattened image array (row-major): index = row*IN1_W + col
    reg signed [7:0] in_img [0:IN1_H*IN1_W-1];
    // weights: [i][j][ch]
    reg signed [7:0] w_conv1 [0:K_H-1][0:K_W-1][0:CHAN-1];

    wire done;
    wire signed [7:0] out_pixel; // matches conv1 port
    wire [7:0] out_addr; // conv1 has this as reg output; connect as wire from DUT

    // instantiate DUT
    conv1 #(
        .K_H(K_H),
        .K_W(K_W),
        .IN1_H(IN1_H),
        .IN1_W(IN1_W),
        .OUT1_H(OUT1_H),
        .OUT1_W(OUT1_W),
        .CHAN(CHAN)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .trigger(trigger),
        .in_img(in_img),
        .w_conv1(w_conv1),
        .done(done),
        .out_pixel(out_pixel),
        .out_addr(out_addr)
    );

    // clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    integer i,j,k,idx;
    initial begin
        // dump
        $dumpfile("test_conv1.vcd");
        $dumpvars(0, tb_conv1);

        // init
        rst_n = 0;
        trigger = 0;

        // initialize image with deterministic values
        for (idx = 0; idx < IN1_H*IN1_W; idx = idx + 1) begin
            // range -16..15 pattern
            in_img[idx] = $signed((idx % 32) - 16);
        end

        // initialize weights small
        for (i=0;i<K_H;i=i+1) begin
            for (j=0;j<K_W;j=j+1) begin
                for (k=0;k<CHAN;k=k+1) begin
                    w_conv1[i][j][k] = $signed(((i* K_W + j + k) % 7) - 3);
                end
            end
        end

        // reset
        #20;
        rst_n = 1;
        #20;

        // pulse trigger one cycle
        @(posedge clk);
        trigger = 1;
        @(posedge clk);
        trigger = 0;

        // wait for DUT to assert done
        wait(done == 1);
        // give a few cycles to ensure last outputs observed
        #50;

        // perform golden-model check by iterating through TOTAL addresses
        integer addr;
        integer mismatch;
        mismatch = 0;
        for (addr = 0; addr < TOTAL; addr = addr + 1) begin
            // compute reference using same mapping as conventional conv:
            // pos = addr % (OUT1_H*OUT1_W); ch = addr / (OUT1_H*OUT1_W)
            integer pos, ch, row, col;
            pos = addr % (OUT1_H*OUT1_W);
            ch = addr / (OUT1_H*OUT1_W);
            row = pos / OUT1_W;
            col = pos % OUT1_W;
            integer ii,jj;
            integer signed [31:0] sum;
            sum = 0;
            for (ii=0; ii<K_H; ii=ii+1) begin
                for (jj=0; jj<K_W; jj=jj+1) begin
                    integer img_r = row + ii;
                    integer img_c = col + jj;
                    integer img_idx = img_r * IN1_W + img_c;
                    // bounds check (should be in range given OUT dims)
                    if (img_idx >= 0 && img_idx < IN1_H*IN1_W) begin
                        sum = sum + $signed(in_img[img_idx]) * $signed(w_conv1[ii][jj][ch]);
                    end
                end
            end
            // reduce to 8-bit as DUT out_pixel is 8-bit (truncate low bits)
            reg signed [7:0] ref8;
            ref8 = $signed(sum[7:0]);

            // Wait until out_addr matches addr (or sample sequentially). We sample on posedge.
            // Wait a couple cycles to let DUT progress; sampling is best-effort here.
            #1;
            // read DUT output: since we cannot directly index historical outputs, print current values when out_addr equals addr
            // Wait until DUT out_addr equals this address or timeout
            integer timeout;
            timeout = 1000;
            while (out_addr !== addr && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                $display("Timeout waiting for addr %0d, DUT addr = %0d", addr, out_addr);
                mismatch = mismatch + 1;
            end else begin
                // sample out_pixel
                reg signed [7:0] dut_val;
                dut_val = out_pixel;
                if (dut_val !== ref8) begin
                    $display("MISATCH at addr=%0d ch=%0d pos=(%0d,%0d): DUT=%0d REF=%0d (sum=%0d)", addr, ch, row, col, dut_val, ref8, sum);
                    mismatch = mismatch + 1;
                end
            end
        end

        if (mismatch == 0) $display("TEST PASS: all outputs matched reference");
        else $display("TEST FAIL: %0d mismatches", mismatch);

        #20;
        $finish;
    end

endmodule