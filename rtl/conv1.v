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
    input wire signed [7:0] in_img [0:IN1_H*IN1_W-1],
    input wire signed [7:0] w_conv1 [K_H][K_W][CHAN],
    output done,
    output wire [7:0] out_pixel,
    output reg [7:0] out_addr
)

localparam S_IDLE = 0,
           S_CALC = 1,
           S_DONE = 2;

reg [2:0] state;

reg signed [7:0] conv_win [K_H-1:0][K_W-1:0];
reg signed [7:0] w [K_H-1:0][K_W-1:0];

conv_unit dut (
    .conv_win(conv_win),
    .w(w),
    .result(out_pixel)
)

// state transfer
always @ (posedge clk) begin
    if (~rst_n) state <= S_IDLE;
    else begin
        case(state)
        S_IDLE: begin
            done <= 0;
            if (trigger) state <= S_CALC;
            else state <= S_IDLE;
        end
        S_CALC: begin
            if (out_addr == OUT1_H * OUT1_W * CHAN -1 ) state <= S_DONE;
            else state <= S_CALC;
        end
        S_DONE: begin
            state <= S_IDLE;
            done <= 1;
        end
        default: state <= S_IDLE;
    endcase
    end
end

task update_conv_opr;
    input wire  [7:0] addr;
    integer i,j;
    begin
        for (i=0;i<K_H;i=i+1) begin
            for (j=0;j<K_W;j=j+1) begin
                conv_win[i][j] = in_img[i + (addr % (OUT1_H*OUT1_W))/OUT1_H][j + (addr % (OUT1_H*OUT1_W))%OUT1_H];
                w[i][j] = w_conv1[i][j][addr/(OUT1_H*OUT1_W)];
            end
        end
    end
endtask

// main loop
always @ (posedge clk) begin
    case(state)
    S_IDLE: begin
        out_addr <= 8'b0;
        out_pixel <= 8'bx;
        update_conv_opr(out_addr);
    end
    S_CALC: begin
        out_addr <= out_addr + 8'b1;
        update_conv_opr(out_addr);
    end
    S_DONE:
    default:
endcase
end
endmodule



module conv_unit (
    input reg signed [7:0] conv_win [K_H-1:0][K_W-1:0],
    input reg signed [7:0] w [K_H-1:0][K_W-1:0],
    output reg signed [15:0] result
)

integer i,j;
always begin
    for (i=0;i<K_H;i=i+1) begin
        for (j=0;j<K_W;j=j+1) begin
            result = result + conv_win[i][j] * w[i][j];
        end
    end
end

endmodule