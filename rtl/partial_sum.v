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

integer i, j, k;
localparam IDLE = 0,
           CALC = 1,
           DONE = 2;
reg[1:0] state;

always @ (posedge clk) begin
    if (~rst_n) begin
        state <= IDLE;
        out_valid <= 0;
        for (i <= 0; i < H; i = i + 1) begin
            for (k <= 0; k < W; k = k + 1) begin
                out_data[i][k] <= 0;
            end
        end
    end
    else begin
        case(state) 
            IDLE: begin
                j <= 0;
                out_valid <= 0;
                if (in_valid) begin
                    state <= CALC;
                end
            end
            CALC: begin
                if (j < W-1) begin
                    for (i = 0; i < H; i = i + 1) begin
                        out_data[i][j] <= out_data[i][j] + in_data[i][j];
                    end
                    j <= j + 1;
                end else begin
                    state <= DONE;
                    for (i <= 0; i < H; i <= i + 1) begin
                        if ({out_data[i][j] + in_data[i][j]}[23] == 1) begin
                            out_data[i][j] <= 24'sd0;
                        end else begin
                            out_data[i][j] <= out_data[i][j] + in_data[i][j];
                        end
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