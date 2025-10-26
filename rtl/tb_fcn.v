
`timescale 1ns/1ps
`include "fc_top.v"

module tb_fcn;
    reg clk;
    reg rst_n;

    reg in_wr;
    reg [7:0] in_addr;
    reg signed [7:0] in_data;

    reg fc1_w_wr;
    reg [15:0] fc1_w_addr;
    reg signed [7:0] fc1_w_data;

    reg fc2_w_wr;
    reg [3:0] fc2_w_addr;
    reg signed [7:0] fc2_w_data;

    reg start;
    wire done;
    wire signed [23:0] fc2_logit;

    fc_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_wr(in_wr),
        .in_addr(in_addr),
        .in_data(in_data),
        .fc1_w_wr(fc1_w_wr),
        .fc1_w_addr(fc1_w_addr),
        .fc1_w_data(fc1_w_data),
        .fc2_w_wr(fc2_w_wr),
        .fc2_w_addr(fc2_w_addr),
        .fc2_w_data(fc2_w_data),
        .start(start),
        .done(done),
        .fc2_logit(fc2_logit)
    );


    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    integer i, n;
    initial begin
        rst_n = 0;
        in_wr = 0; fc1_w_wr = 0; fc2_w_wr = 0; start = 0;
        in_addr = 0; in_data = 0;
        fc1_w_addr = 0; fc1_w_data = 0;
        fc2_w_addr = 0; fc2_w_data = 0;
        #20;
        rst_n = 1;
        #20;

        // For test: fill in_vec with small signed values
        for (i = 0; i < 132; i = i + 1) begin
            @(posedge clk);
            in_wr = 1;
            in_addr = i;
            in_data = (i % 8) - 3; // some signed small values
        end
        @(posedge clk);
        in_wr = 0;

        // write fc1 weights: weight for neuron n and index j : (n+1)
        for (n = 0; n < 10; n = n + 1) begin
            for (i = 0; i < 132; i = i + 1) begin
                @(posedge clk);
                fc1_w_wr = 1;
                fc1_w_addr = n * 132 + i;
                fc1_w_data = (n + 1);
            end
        end
        @(posedge clk);
        fc1_w_wr = 0;

        // write fc2 weights: set all to 1
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            fc2_w_wr = 1;
            fc2_w_addr = i;
            fc2_w_data = 1;
        end
        @(posedge clk);
        fc2_w_wr = 0;

        // start computation
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // wait for done
        wait (done == 1);
        #10;

        $display("=== RESULTS ===");
        // print FC1 outputs via hierarchical access (simulation only)
        for (i = 0; i < 10; i = i + 1) begin
            $display("fc1_out_relu[%0d] = %0d", i, tb_fcn.dut.fc1_out_relu[i]);
        end
        $display("fc2_logit = %0d", fc2_logit);

        $display("Sim done.");
        $finish;
    end

endmodule
