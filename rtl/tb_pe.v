`include "pe_unit.v"
`default_nettype none
`timescale 1ps/1ps

module tb_pe_unit;
reg clk;
reg rst_n;
reg ready;
reg signed [7:0] in_data1 ;
reg signed [7:0] in_data2 ;
wire  signed [23:0] outdata;
// wire done;

pe_unit dut1
(
    .rst_n (rst_n),
    .clk (clk),
    .ready(ready),
    .in_data1(in_data1),
    .in_data2(in_data2),
    .outdata(outdata)
    // .done(done)
);

localparam CLK_PERIOD = 2;
always #(CLK_PERIOD/2) clk=~clk;

initial begin
    $dumpfile("tb_pe_unit.vcd");
    $dumpvars(0, tb_pe_unit);
end

initial begin
    #1 rst_n<=1'b1;clk<=1'b0;
    in_data1 <= 8'd2;
    in_data2 <= 8'd3;
    ready <= 0;
    #(CLK_PERIOD*3) rst_n<=0;
    #(CLK_PERIOD*3) rst_n<=1;
    @(posedge clk);
    ready <= 1;
    @(posedge clk);
    ready <=0;
    repeat(2) @(posedge clk);
    in_data1 <= -8'd1;
    in_data2 <=8'd2;
    @(posedge clk);
    ready <= 1;
    @(posedge clk);
    ready <= 0;
    repeat(5) @(posedge clk);
    $finish(2);
end

endmodule
`default_nettype wire