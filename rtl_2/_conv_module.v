module conv #(
    K_H = 3,
    K_W = 3,
    MAX_H = 16,
    MAX_W = 15,
    NUM_UNITS = 1,
    DATA_WIDTH = 8
)(
    input clk,
    input rst_n,
    input clear,
    input trigger,
    input save_done,
    input wire layer, // 0 for conv1, 1 for conv2
    input wire [DATA_WIDTH-1:0] in_img [0 : MAX_H * MAX_W - 1], // buffer to read input image, 16*15 = 240B
    input wire signed [DATA_WIDTH-1:0] w_conv [K_H][K_W], // buffer to read weight for a single channel, 3*3 = 9B
    output reg valid, // out_pixel valid signal
    output wire signed [23:0] out_pixel, // output pixel after convolution and ReLU (if needed)
    output reg [7:0] addr // address to read input image
);

localparam S_IDLE = 0,
           S_CALC = 1,
           S_WAIT = 2,
           S_DONE = 3;

wire [3:0] in_w = layer ? 13 : 15;

reg [2:0] state;

reg signed [8:0] conv_win [0:K_H-1][0:K_W-1];

task update_conv_opr;
    input [7:0] addr;
    input [3:0] in_w;
    integer i,j, row, col, out_w;
    out_w = in_w - K_W + 1;
    row = addr / out_w;
    col = addr % out_w;
    begin
        for (i=0;i<K_H;i=i+1) begin
            for (j=0;j<K_W;j=j+1) begin
                conv_win[i][j] <= {1'b0, in_img[(i+row) * in_w + j + col]};
            end
        end
    end
endtask

conv_unit #(
    .K_H(K_H),
    .K_W(K_W),
    .IN_DATA_WIDTH(9),
    .OUT_DATA_WIDTH(8)
) u_conv_unit (
    .conv_win(conv_win),
    .w(w_conv),
    .en_relu(~layer), // ReLU enabled for conv1
    .out_pixel(out_pixel)
);

// main loop
always @ (posedge clk) begin
    if (~rst_n || clear) begin
        state <= S_IDLE;
        valid <= 0;
        addr <= 8'b0;
    end else begin
        case(state)
        S_IDLE: begin
            valid <= 0;
            addr <= 8'b0;
            if (trigger) begin
                state <= S_CALC;
            end
            else begin
                state <= S_IDLE;
            end
        end
        S_CALC: begin
            valid <= 1;
            update_conv_opr(addr, in_w);
            state <= S_WAIT;
        end
        S_WAIT: begin
            valid <= 0;
            if (save_done) begin
                addr <= addr + 8'b1;
                state <= S_CALC;
            end else begin
                state <= S_WAIT;
            end
        end
        default: begin                  // 删去了S_DONE状态，需要在换channel时reset卷积模块
            state <= S_IDLE;
            valid <= 0;
            addr <= 8'b0;
        end
    endcase
    end
end

endmodule