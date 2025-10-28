module conv1 #(
    K_H = 3,
    K_W = 3,
    CHAN = 10
)(
    input clk,
    input rst_n,
    input trigger,
    input wire signed [7:0] in_img [0:IN1_H*IN1_W-1],
    input wire signed [7:0] in_img [K_H][K_W][CHAN],
)

 sram dut(

 );


endmodule


module sram()

endmodule