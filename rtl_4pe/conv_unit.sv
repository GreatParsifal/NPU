module conv_unit # (
    parameter K_H = 3,
    parameter K_W = 3,
)(
    input clk,
    input ready,
    input logic [7:0] img [K_H-1:0][K_W-1:0],
    input logic signed [7:0] w [K_H-1:0][K_W-1:0],
    output logic signed [23:0] result
);

// product wires
logic signed [23:0] acc;
integer i, j;

always_comb begin: acc_logic
    acc = 0;
    for (i=0;i<K_H;i=i+1) begin
        for (j=0;j<K_W;j=j+1) begin
            acc = acc + $signed({1'b0, img[i][j]}) * $signed(w[i][j]);
        end
    end
end

// combinational accumulation of products
integer k;
always_ff @ (posedge clk) begin
    if (ready) begin
        result <= acc; // do relu in npu
    end else begin
        result <= 24'b0;
    end
end

endmodule