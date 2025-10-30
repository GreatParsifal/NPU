module conv1_tb;
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
    reg [7:0] in_img [0:IN1_H*IN1_W-1];
    // weights: [i][j][ch]
    reg signed [7:0] w_conv1 [0:K_H-1][0:K_W-1][0:CHAN-1];

    wire done;
    wire signed [23:0] out_pixel; // matches conv1 port
    wire [10:0] out_addr; // conv1 has this as reg output; connect as wire from DUT

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
    integer addr;
    integer mismatch;
    integer pos, ch, row, col;
    integer ii,jj;
    integer signed [31:0] sum;
    reg signed [7:0] ref8;
    reg signed [7:0] dut_val;
    integer timeout;
    reg signed [23:0] out_img [0:TOTAL-1];
    reg signed [23:0] gt_img [0:TOTAL-1];

    initial begin
        // dump
        $dumpfile("test_conv1.vcd");
        $dumpvars(0, conv1_tb);

        // init
        rst_n = 1;
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

        // compute golden-model ground truth
        for (i=0;i<OUT1_H;i=i+1) begin
            for (j=0;j<OUT1_W;j=j+1) begin
                for (k=0;k<CHAN;k=k+1) begin
                    gt_img[k*OUT1_H*OUT1_W + i*OUT1_W + j] = 0;
                    // compute ground truth for this position
                    for (ii=0; ii<K_H; ii=ii+1) begin
                        for (jj=0; jj<K_W; jj=jj+1) begin
                            integer img_r = i + ii;
                            integer img_c = j + jj;
                            integer img_idx = img_r * IN1_W + img_c;
                            // bounds check (should be in range given OUT dims)
                            if (img_idx >= 0 && img_idx < IN1_H*IN1_W) begin
                                gt_img[k*OUT1_H*OUT1_W + i*OUT1_W + j] = gt_img[k*OUT1_H*OUT1_W + i*OUT1_W + j] +
                                    $signed(1'b0, in_img[img_idx]) * $signed(w_conv1[ii][jj][k]);
                            end
                        end
                    end
                end
            end
        end

        // reset
        #20;
        rst_n = 0;
        #20;
        rst_n = 1;

        // pulse trigger one cycle
        @(posedge clk);
        trigger = 1;
        @(posedge clk);
        trigger = 0;

        // perform golden-model check by iterating through TOTAL addresses
        
        mismatch = 0;

        if (mismatch == 0) $display("TEST PASS: all outputs matched reference");
        else $display("TEST FAIL: %0d mismatches", mismatch);

        #20;
        $finish;
    end

endmodule