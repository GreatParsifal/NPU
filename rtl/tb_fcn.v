// tb_fcn.v - Verilator TB for fcn (bulk array writes)
`timescale 1ns/1ps
`include "fcn.v"

module tb_fcn;
    reg clk;
    reg rst_n;

    // bulk write interfaces for fcn
    reg                             in_vec_wr;
    reg  signed [7:0]               in_vec_array   [0:132-1];
    reg                             fc1_w_wr_all;
    reg  signed [7:0]               fc1_w_array    [0:10-1][0:132-1];
    reg                             fc2_w_wr_all;
    reg  signed [7:0]               fc2_w_array    [0:10-1];

    reg start;
    wire done;
    wire signed [23:0] fc2_logit;

    // instantiate DUT
    fcn #(.IN1_N(132), .OUT1_M(10)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_vec_wr(in_vec_wr),
        .in_vec_array(in_vec_array),
        .fc1_w_wr_all(fc1_w_wr_all),
        .fc1_w_array(fc1_w_array),
        .fc2_w_wr_all(fc2_w_wr_all),
        .fc2_w_array(fc2_w_array),
        .start(start),
        .done(done),
        .fc2_logit(fc2_logit)
    );

    // clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz-ish for sim
    end

    integer i, n;
    initial begin
        // reset
        rst_n = 0;
        in_vec_wr = 0; fc1_w_wr_all = 0; fc2_w_wr_all = 0; start = 0;
        #20;
        rst_n = 1;
        #20;

        // prepare sample input vector (132 elements)
        for (i = 0; i < 132; i = i + 1) begin
            in_vec_array[i] = (i % 8) - 3; // some signed small values
        end
        // write in_vec in one cycle
        @(posedge clk); in_vec_wr = 1; @(posedge clk); in_vec_wr = 0;

        // prepare fc1 weights: neuron n, index j -> (n+1)
        for (n = 0; n < 10; n = n + 1) begin
            for (i = 0; i < 132; i = i + 1) begin
                fc1_w_array[n][i] = (n + 1);
            end
        end
        // write all fc1 weights in one cycle
        @(posedge clk); fc1_w_wr_all = 1; @(posedge clk); fc1_w_wr_all = 0;

        // prepare fc2 weights: all ones
        for (i = 0; i < 10; i = i + 1) begin
            fc2_w_array[i] = 8'sd1;
        end
        // write all fc2 weights in one cycle
        @(posedge clk); fc2_w_wr_all = 1; @(posedge clk); fc2_w_wr_all = 0;

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
