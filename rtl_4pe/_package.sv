module pack (
    input logic clk,
    input logic rst_n,
    input logic in_valid,
    input logic clear,
    input logic [23:0] in_data,
    output logic [31:0] out_data
);

logic [7:0] register [0:3];
logic [1:0] addr;

genvar gi;
generate
    for (gi=0;gi<4;gi=gi+1) begin
        assign out_data[gi*8+7:gi*8] = register[gi];
    end
endgenerate

always_ff @(posedge clk) begin
    if (~rst_n || clear) begin
        for (int i=0;i<4;i=i+1) begin
            register[i] = 8'b0;
        end
        addr <= 2'b0;
    end else if (in_valid) begin
        register[addr] <= in_data[7:0];
        addr <= addr + 1;
    end
end

endmodule