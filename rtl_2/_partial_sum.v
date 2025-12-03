module partial_sum #(
    parameter IN_DATA_WIDTH = 24,
    parameter OUT_DATA_WIDTH = 8,
    parameter H = 12,
    parameter W = 11,
    parameter CHAN = 10
)(
    input clk,
    input rst_n,
    input in_valid,
    input wire [3:0] cal_chan,
    input wire signed [IN_DATA_WIDTH-1:0] in_data [0:H-1][0:W-1],
    output wire [OUT_DATA_WIDTH-1:0] out_data [0:H-1][0:W-1],
    output reg out_valid
);

reg signed [IN_DATA_WIDTH-1:0] sum_data [0:H-1][0:W-1];

genvar ii, jj;

for (ii = 0; ii < H; ii = ii + 1) begin
    for (jj = 0; jj < W; jj = jj + 1) begin
        assign out_data[ii][jj] = sum_data[ii][jj][OUT_DATA_WIDTH-1:0];
    end
end

localparam IDLE = 0,
           CALC = 1,
           DONE = 2;
reg[1:0] state;

integer i, j;

always @ (posedge clk) begin
    if (~rst_n) begin
        state <= IDLE;
        out_valid <= 0;
        for (i = 0; i < H; i = i + 1) begin
            for (j = 0; j < W; j = j + 1) begin
                sum_data[i][j] <= 0;
            end
        end
    end
    else begin
        case(state) 
            IDLE: begin
                out_valid <= 0;
                if (in_valid) begin
                    state <= CALC;
                end
            end
            CALC: begin
                for (i = 0; i < H; i = i + 1) begin
                    sum_data[i][cal_chan] <= sum_data[i][cal_chan] + in_data[i][cal_chan];
                end
                if (cal_chan == CHAN-1) begin
                    state <= DONE;
                end
            end
            DONE: begin
                if (cal_chan == 4'd9) begin
                    out_valid <= 1;
                    for (i = 0; i < H; i = i + 1) begin
                        sum_data[i][cal_chan] <= sum_data[i][cal_chan][23] ? 24'b0 : sum_data[i][cal_chan]; // Relu
                    end
                end
                state <= IDLE;
            end
        endcase
    end
end

endmodule