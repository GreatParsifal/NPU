module buffer #(
    parameter DATA_WIDTH = 24,
    parameter H = 14,
    parameter W = 13
)(
    input clk,
    input in_valid,
    input wire [DATA_WIDTH-1:0] in_data [0:H-1][0:W-1],
    output reg signed [DATA_WIDTH-1:0] out_data [0:H-1][0:W-1]
);

integer i, j;
always @ (posedge clk) begin
    if (in_valid) begin
        for (i = 0; i < H; i = i + 1) begin
            for (j = 0; j < W; j = j + 1) begin
                out_data[i][j] <= in_data[i][j];
            end
        end
    end
end

endmodule