module partial_sum #(
    parameter DATA_WIDTH = 24,
    parameter H = 12,
    parameter W = 11
)(
    input clk,
    input ce,
    input rst_n,
    input clear,
    input wire [7:0] addr,
    input wire signed [DATA_WIDTH-1:0] in_data,
    input wire in_valid,
    output reg signed [DATA_WIDTH-1:0] out_data [0:H-1][0:W-1]
);

integer i, j; // ptrs
integer row, col;

always @(posedge clk) begin
    if (~ce) begin
        // do nothing
    end
    else if (~rst_n || clear) begin
        for (i=0; i<H; i=i+1) begin
            for (j=0; j<W; j=j+1) begin
                out_data[i][j] <= 0;
            end
        end
    end
    else if (in_valid) begin
        row = addr / W;
        col = addr % W;
        out_data[row][col] <= out_data[row][col] + in_data;
        out_valid <= 1;
    end else begin
        out_valid <= 0;
    end
end

endmodule