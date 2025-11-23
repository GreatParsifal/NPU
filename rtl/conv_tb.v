module conv_tb;
    // parameters should match conv1 defaults
    parameter K_H = 3;
    parameter K_W = 3;
    parameter IN1_H = 16;
    parameter IN1_W = 15;
    parameter OUT1_H = 14;
    parameter OUT1_W = 13;
    parameter OUT2_H = 12;
    parameter OUT2_W = 11;
    parameter CHAN = 10;

    // signals
    reg clk;
    reg rst_n;
    reg trigger;

    // input arrays (match conv1 ports) - use signed for easy reference math
    reg [7:0] in_img [0:IN1_H-1][0:IN1_W-1];
    reg signed [7:0] w_conv1 [0:K_H-1][0:K_W-1][0:CHAN-1];
    reg signed [7:0] w_conv2 [0:K_H-1][0:K_W-1][0:CHAN-1];

    // outputs from DUT
    wire out_valid;
    // out_buff is 2D array of signed [23:0]
    wire signed [23:0] out_buff [0:OUT2_H-1][0:OUT2_W-1];
    integer finished_chan_count;
    integer mismatches;
    integer cycles_wait;
    integer ch;
    integer ii, jj;

    reg signed [23:0] conv1_out [0:OUT1_H-1][0:OUT1_W-1];
    reg signed [23:0] conv2_out [0:OUT2_H-1][0:OUT2_W-1];
    reg signed [23:0] golden [0:OUT2_H-1][0:OUT2_W-1];
    reg prev_valid;

    // instantiate DUT
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
        .out_valid(out_valid)
    );

    // clock generator
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10 ns period
    end

    integer i,j,k,ri,cj;

    // initialize data, apply reset, pulse trigger, and check outputs
    initial begin

        // defaults
        rst_n = 0;
        trigger = 0;

        // initialize image with deterministic pattern (signed values)
        for (i = 0; i < IN1_H; i = i + 1) begin
            for (j = 0; j < IN1_W; j = j + 1) begin
                in_img[i][j] = $random();
            end
        end

        // initialize weights small signed values
        for (i = 0; i < K_H; i = i + 1) begin
            for (j = 0; j < K_W; j = j + 1) begin
                for (k = 0; k < CHAN; k = k + 1) begin
                    w_conv1[i][j][k] = $random() % 19 - 9; // values from -2 to +2
                    w_conv2[i][j][k] = $random() % 5 - 2; // values from -2 to +2
                end
            end
        end

        // reset pulse
        #20;
        rst_n = 1; // release reset
        #20;

        // pulse trigger for start
        @(posedge clk);
        trigger = 1;
        @(posedge clk);
        trigger = 0;

        // monitor out_valid rising edges and check results per-channel
        
        finished_chan_count = 0;
       
        mismatches = 0;

        // previous out_valid for edge detection
        
        prev_valid = 0;

        // wait until all channels are produced or timeout
        
        cycles_wait = 0;
        while (finished_chan_count < 1 && cycles_wait < 20000000) begin
            @(posedge clk);
            cycles_wait = cycles_wait + 1;
            if (out_valid && !prev_valid) begin
                // rising edge: capture channel index
                $display("Detected out_valid at time %0t", $time);

                // compute golden output with result from dut
                for (ri = 0; ri < OUT2_H; ri = ri + 1) begin
                    for (cj = 0; cj < OUT2_W; cj = cj + 1) begin
                        golden[ri][cj] = 0;
                    end
                end
                for (ch = 0; ch < CHAN; ch = ch + 1) begin
                    for (ri = 0; ri < OUT1_H; ri = ri + 1) begin
                        for (cj = 0; cj < OUT1_W; cj = cj + 1) begin
                            
                            conv1_out[ri][cj] = 0;
                            for (ii = 0; ii < K_H; ii = ii + 1) begin
                                for (jj = 0; jj < K_W; jj = jj + 1) begin
                                    // input pixel at (ri+ii, cj+jj)
                                    conv1_out[ri][cj] = conv1_out[ri][cj] + $signed({1'b0, in_img[ri+ii][cj+jj]}) * $signed(w_conv1[ii][jj][ch]);
                                end
                            end
                            conv1_out[ri][cj] = conv1_out[ri][cj][23] ? 24'b0 : conv1_out[ri][cj]; // ReLU
                        end
                    end
                    for (ri = 0; ri < OUT2_H; ri = ri + 1) begin
                        for (cj = 0; cj < OUT2_W; cj = cj + 1) begin
                            conv2_out[ri][cj] = 0;
                            for (ii = 0; ii < K_H; ii = ii + 1) begin
                                for (jj = 0; jj < K_W; jj = jj + 1) begin
                                    // input pixel at (ri+ii, cj+jj)
                                    conv2_out[ri][cj] = conv2_out[ri][cj] + $signed(conv1_out[ri+ii][cj+jj]) * $signed(w_conv2[ii][jj][ch]);
                                end
                            end
                        end
                    end
                    for (ri = 0; ri < OUT2_H; ri = ri + 1) begin
                        for (cj = 0; cj < OUT2_W; cj = cj + 1) begin
                            golden[ri][cj] += conv2_out[ri][cj];
                        end
                    end
                    for (ri = 0; ri < OUT2_H; ri = ri + 1) begin
                        for (cj = 0; cj < OUT2_W; cj = cj + 1) begin
                            golden[ri][cj] = golden[ri][cj][23] ? 24'b0 : golden[ri][cj]; // ReLU
                        end
                    end
                end // channel loop
                if (out_buff[ri][cj] !== golden[ri][cj]) begin
                    $display("Mismatch ch=%0d pos=(%0d,%0d): DUT=%0d REF=%0d", ch, ri, cj, out_buff[ri][cj], golden[ri][cj]);
                    mismatches = mismatches + 1;
                end

                finished_chan_count = finished_chan_count + 1;
            end
            prev_valid = out_valid;
        end

        if (cycles_wait >= 20000000) begin
            $display("\nTimeout waiting for channels, finished %0d/%0d\n", finished_chan_count, CHAN);
        end

        if (mismatches == 0) begin
            $display("\nconv_tb: TEST PASS - all channels matched reference\n");
            $display("Final output buffer:");
            for (ri = 0; ri < OUT2_H; ri = ri + 1) begin
                for (cj = 0; cj < OUT2_W; cj = cj + 1) begin
                    $write("%0d ", out_buff[ri][cj]);
                end
                $write("\n");
            end
            $display("Final golden buffer:");
            for (ri = 0; ri < OUT2_H; ri = ri + 1) begin
                for (cj = 0; cj < OUT2_W; cj = cj + 1) begin
                    $write("%0d ", golden[ri][cj]);
                end
                $write("\n");
            end
        end
        else $write("\nconv1_tb: TEST FAIL - %0d mismatches found\n", mismatches);

        #100;
        $finish;
    end

    initial begin
        $fsdbDumpfile("conv_tb.fsdb");
        $fsdbDumpvars(0, conv_tb);
        $fsdbDumpMDA();
    end

endmodule
