module conv_unit # (
    parameter K_H = 3,
    parameter K_W = 3
)(
    input [7:0] conv_win [K_H-1:0][K_W-1:0],
    input signed [7:0] w [K_H-1:0][K_W-1:0],
    output reg signed [23:0] result
);

localparam N = K_H * K_W;

// product wires
wire signed [23:0] prod [0:N-1];

genvar gi, gj;
generate
    for (gi = 0; gi < K_H; gi = gi + 1) begin : GEN_ROW
        for (gj = 0; gj < K_W; gj = gj + 1) begin : GEN_COL
            // compute linear index for the product array
            localparam integer IDX = gi * K_W + gj;
            assign prod[IDX] = $signed({1'b0, conv_win[gi][gj]}) * $signed(w[gi][gj]);
        end
    end
endgenerate

// combinational accumulation of products
integer k;
always @* begin
    result = 0;
    for (k = 0; k < N; k = k + 1) begin
        result = result + prod[k];
    end
    result = result[23] ? 24'b0 : result; // ReLU
end

endmodule