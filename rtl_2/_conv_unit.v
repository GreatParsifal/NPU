module conv_unit # (
    parameter K_H = 3,
    parameter K_W = 3,
    parameter IN_DATA_WIDTH = 9,
    parameter OUT_DATA_WIDTH = 8
)(
    input signed [IN_DATA_WIDTH-1:0] conv_win [K_H-1:0][K_W-1:0],
    input signed [7:0] w [K_H-1:0][K_W-1:0],
    input en_relu,
    output wire signed [23:0] out_pixel
);

localparam N = K_H * K_W;

// product wires
wire signed [23:0] prod [0:N-1];
reg signed [23:0] result; // intermediate result

assign out_pixel = result;

genvar gi, gj;
generate
    for (gi = 0; gi < K_H; gi = gi + 1) begin : GEN_ROW
        for (gj = 0; gj < K_W; gj = gj + 1) begin : GEN_COL
            // compute linear index for the product array
            localparam integer IDX = gi * K_W + gj;
            assign prod[IDX] = $signed(conv_win[gi][gj]) * $signed(w[gi][gj]);
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
    if (en_relu && result < 0) begin
        result = 0;
    end
end

endmodule