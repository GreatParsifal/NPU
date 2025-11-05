module conv1 #(
    K_H = 3,
    K_W = 3,
    IN1_H = 16,
    IN1_W = 15,
    OUT1_H = 14,
    OUT1_W = 13,
    CHAN = 10
)(
    input clk,
    input rst_n,
    input trigger,
    input wire [7:0] in_img [0:IN1_H-1][0:IN1_W-1],
    input wire signed [7:0] w_conv1 [K_H][K_W][CHAN],
    output reg signed [23:0] out_buff [0:OUT1_H-1][0:OUT1_W-1],
    output reg out_valid,
    output reg [3:0] out_chan
);

localparam S_IDLE = 0,
           S_CALC = 1,
           S_DONE = 2;

reg [2:0] state;
reg [7:0] out_addr;
reg [23:0] out_pixel;
reg [3:0] cal_chan;

reg [7:0] conv_win [0:K_H-1][0:K_W-1];
reg signed [7:0] w [0:K_H-1][0:K_W-1];

conv_unit dut (
    .conv_win(conv_win),
    .w(w),
    .result(out_pixel)
);

task update_conv_opr;
    input [7:0] addr;
    input [3:0] chan;
    integer i,j;
    begin
        for (i=0;i<K_H;i=i+1) begin
            for (j=0;j<K_W;j=j+1) begin
                conv_win[i][j] <= in_img[i + (addr/OUT1_W)][j + addr % OUT1_W];
                w[i][j] <= w_conv1[i][j][chan];
            end
        end
    end
endtask

// main loop
always @ (posedge clk) begin
    if (~rst_n) state <= S_IDLE;
    else begin
        case(state)
        S_IDLE: begin
            out_valid <= 0;
            cal_chan <= 4'b0;
            out_addr <= 8'b0;
            update_conv_opr(out_addr, cal_chan);
            if (trigger) begin
                state <= S_CALC;   
            end
            else begin
                state <= S_IDLE;
            end
        end
        S_CALC: begin
            out_valid <= 0;
            update_conv_opr(out_addr, cal_chan);
            if (out_addr > 0) begin
                out_buff[(out_addr-1) / OUT1_W][(out_addr-1) % OUT1_W] <= out_pixel;
            end
            if (out_addr == OUT1_H * OUT1_W -1 ) begin
                state <= S_DONE;
            end
            else begin
                state <= S_CALC;
                out_addr <= out_addr + 8'b1;
            end
        end
        S_DONE: begin
            out_buff[out_addr / OUT1_W][out_addr % OUT1_W] <= out_pixel;
            out_valid <= 1;
            out_chan <= cal_chan;
            if (cal_chan == CHAN-1) state <= S_IDLE;
            else begin
                state <= S_CALC;
                out_addr <= 8'b0;
                cal_chan <= cal_chan + 4'b1;
            end
        end
        default: state <= S_IDLE;
    endcase
    end
end

endmodule