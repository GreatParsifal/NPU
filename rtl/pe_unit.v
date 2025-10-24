module pe_unit(
    input clk;
    input rst;
    input ready;
    input wire signed in_data1 [7:0];
    input wire signed in_data2 [7:0];
    output reg outdata[23:0];
    output done;
);

localparam IDLE = 0, CALC = 1;
reg state;

//state transfer
always @ (posedge clk) begin
    if (rst) begin
        state <= IDLE;
    end
    else begin
        if (~ready) state <= IDLE;
        else begin
            if (~done) state <= CALC;
            else state <= IDLE;
        end
    end
end

always @ (posedge clk) begin
    if (rst) begin
        outdata = 24'b0;
        done = 0;
    end else begin

    end
end


endmodule