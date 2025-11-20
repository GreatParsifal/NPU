module conv #(
    K_H = 3,
    K_W = 3,
    IN1_H = 16,
    IN1_W = 15,
    OUT1_H = 14,
    OUT1_W = 13,
    OUT2_H = 12,
    OUT2_W = 11,
    CHAN = 10
)(
    input clk,
    input rst_n,
    input trigger,
    input wire [7:0] in_img [0:IN1_H-1][0:IN1_W-1],
    input wire signed [7:0] w_conv1 [0:K_H-1][0:K_W-1][0:CHAN-1],
    input wire signed [7:0] w_conv2 [0:K_H-1][0:K_W-1][0:CHAN-1],
    output reg signed [23:0] out_buff [0:OUT2_H-1][0:OUT2_W-1],
    output reg out_valid,
    output [3:0] out_chan
);

wire signed [23:0] conv1_out [0:OUT1_H-1][0:OUT1_W-1];
wire signed [23:0] conv2_in [0:OUT1_H-1][0:OUT1_W-1];
wire conv1_out_valid;
wire [3:0] conv1_out_chan;

conv1 #(
    .K_H(K_H),
    .K_W(K_W),
    .IN_H(IN1_H),
    .IN_W(IN1_W),
    .OUT_H(OUT1_H),
    .OUT_W(OUT1_W),
    .CHAN(CHAN)
) conv1_inst (
    .clk(clk),
    .rst_n(rst_n),
    .trigger(trigger),
    .in_img(in_img),
    .w_conv1(w_conv1),
    .out_buff(conv1_out),
    .out_valid(conv1_out_valid),
    .out_chan(conv1_out_chan)  
);

buffer #(
    .DATA_WIDTH(24),
    .H(OUT1_H),
    .W(OUT1_W)
) conv1_buffer (
    .clk(clk),
    .in_valid(conv1_out_valid),
    .in_data(conv1_out),
    .out_data(conv2_in)
);

conv2 #(
    .K_H(K_H),
    .K_W(K_W),
    .IN_H(OUT1_H),
    .IN_W(OUT1_W),
    .OUT_H(OUT2_H),
    .OUT_W(OUT2_W),
    .CHAN(CHAN)
) conv2_inst (
    .clk(clk),
    .rst_n(rst_n),
    .trigger(conv1_out_valid), // trigger on conv1 valid
    .in_img(conv2_in), // input from conv1 buffer
    .w_conv1(w_conv2), // weights for conv2
    .out_buff(out_buff), // final output buffer
    .out_valid(out_valid), // final output valid
    .cal_chan(conv1_out_chan),  // final output channel
    .out_chan(out_chan)
);

endmodule