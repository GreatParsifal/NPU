module partial_sum #(
    parameter DATA_WIDTH = 24,
    parameter H = 12,
    parameter W = 11
)(
    input clk,
    input rst_n,
    input in_valid,
    input wire [3:0] cal_chan,
    input wire signed [DATA_WIDTH-1:0] in_data [0:H-1][0:W-1],
    output reg signed [DATA_WIDTH-1:0] out_data [0:H-1][0:W-1],
    output reg out_valid
);

integer i, j;
localparam IDLE = 0,
           CALC = 1,
           DONE = 2;
reg[1:0] state;

always @ (posedge clk) begin
    if (~rst_n) begin
        state <= IDLE;
        out_valid <= 0;
        for (i = 0; i < H; i = i + 1) begin
            for (j = 0; j < W; j = j + 1) begin
                out_data[i][j] <= 0;
            end
        end
    end
    else begin
        case(state) 
            IDLE: begin
                i <= 0;
                j <= 0;
                out_valid <= 0;
                if (in_valid) begin
                    state <= CALC;
                end
            end
            CALC: begin
                for (i = 0; i < H; i = i + 1) begin
                    out_data[i][j] <= out_data[i][j] + in_data[i][j];
                end
                j += 1;
                if (j == W) begin
                    state <= DONE;
                    for (i = 0; i < H; i = i + 1) begin
                        out_data[i][j] <= out_data[i][j][DATA_WIDTH-1] ? 0 : out_data[i][j]; // ReLU
                    end
                end
            end
            DONE: begin
                if (cal_chan == 4'd9) begin
                    out_valid <= 1;
                end
                state <= IDLE;
            end
        endcase
    end
end

endmodule