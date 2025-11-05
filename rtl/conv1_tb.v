module conv1_tb;
    // parameters should match conv1 defaults
    parameter K_H = 3;
    parameter K_W = 3;
    parameter IN1_H = 16;
    parameter IN1_W = 15;
    parameter OUT1_H = 14;
    parameter OUT1_W = 13;
    parameter CHAN = 10;

    // signals
    reg clk;
    reg rst_n;
    reg trigger;

    // input arrays (match conv1 ports) - use signed for easy reference math
    reg [7:0] in_img [0:IN1_H-1][0:IN1_W-1];
    reg signed [7:0] w_conv1 [0:K_H-1][0:K_W-1][0:CHAN-1];

    // outputs from DUT
    wire out_valid;
    wire [3:0] out_chan;
    // out_buff is 2D array of signed [23:0]
    wire signed [23:0] out_buff [0:OUT1_H-1][0:OUT1_W-1];
    integer finished_chan_count;
    integer mismatches;
    integer cycles_wait;
    integer ch;
    integer ii, jj;
    integer signed [63:0] sum;
    reg signed [23:0] ref24;
    reg prev_valid;

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
        .out_buff(out_buff),
        .out_valid(out_valid),
        .out_chan(out_chan)
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
                // pattern: range -16..+15
                in_img[i][j] = $random();
            end
        end

        // initialize weights small signed values
        for (i = 0; i < K_H; i = i + 1) begin
            for (j = 0; j < K_W; j = j + 1) begin
                for (k = 0; k < CHAN; k = k + 1) begin
                    w_conv1[i][j][k] = $random();
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
        while (finished_chan_count < CHAN && cycles_wait < 200000) begin
            @(posedge clk);
            cycles_wait = cycles_wait + 1;
            if (out_valid && !prev_valid) begin
                // rising edge: capture channel index
                
                ch = out_chan;
                $display("Detected out_valid for channel %0d at time %0t", ch, $time);

                // compute reference for this channel and compare whole out_buff
                for (ri = 0; ri < OUT1_H; ri = ri + 1) begin
                    for (cj = 0; cj < OUT1_W; cj = cj + 1) begin
                        
                        ref24 = 0;
                        for (ii = 0; ii < K_H; ii = ii + 1) begin
                            for (jj = 0; jj < K_W; jj = jj + 1) begin
                                // input pixel at (ri+ii, cj+jj)
                                ref24 = ref24 + $signed({1'b0, in_img[ri+ii][cj+jj]}) * $signed(w_conv1[ii][jj][ch]);
                            end
                        end
                        ref24 = ref24[23] ? 24'b0 : ref24; // ReLU
                        // DUT stores 24-bit signed result per element (out_buff)
                        // compare lower 24 bits (signed)
                        if (out_buff[ri][cj] !== ref24) begin
                            $display("Mismatch ch=%0d pos=(%0d,%0d): DUT=%0d REF=%0d sum=%0d", ch, ri, cj, out_buff[ri][cj], ref24, sum);
                            mismatches = mismatches + 1;
                        end
                    end
                end

                finished_chan_count = finished_chan_count + 1;
            end
            prev_valid = out_valid;
        end

        if (cycles_wait >= 200000) begin
            $display("\nTimeout waiting for channels, finished %0d/%0d\n", finished_chan_count, CHAN);
        end

        if (mismatches == 0) $display("\nconv1_tb: TEST PASS - all channels matched reference\n");
        else $display("\nconv1_tb: TEST FAIL - %0d mismatches found\n", mismatches);

        #100;
        $finish;
    end

    initial begin
        $fsdbDumpfile("conv1_tb.fsdb");
        $fsdbDumpvars(0, conv1_tb);
        $fsdbDumpMDA();
    end

endmodule
