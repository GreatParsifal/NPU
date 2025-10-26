module pe_unit_fcn(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              clr,       // fcn need a logic to clear accumulators
    input  wire              ready,     
    input  wire signed [7:0] in_data1,  // weight
    input  wire signed [7:0] in_data2,  // input
    output reg  signed [23:0] outdata
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            outdata <= 24'sd0;
        end else if (clr) begin
            outdata <= 24'sd0;
        end else if (ready) begin
            outdata <= outdata + $signed(in_data1) * $signed(in_data2);
        end
    end
endmodule
