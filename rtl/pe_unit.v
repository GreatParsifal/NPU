module pe_unit(
    input clk,
    input rst_n,
    input ready,
    input wire signed [7:0] in_data1 ,
    input wire signed [7:0] in_data2 ,
    output reg signed [23:0] outdata
);

localparam IDLE = 0, CALC = 1;
// reg [1:0] state;
reg state;

//state transfer
always @ (posedge clk) begin
    if (~rst_n) begin
        state <= IDLE;
    end
    else begin
        case(state)
            IDLE: begin
                if (~ready) state <= IDLE;
                else state <= CALC;
            end
            CALC: begin
                state <= IDLE;
            end
            default state <= IDLE;
        endcase
    end
end

//calculation
always @ (posedge clk) begin
    if (~rst_n) begin
        outdata <= 24'b0;
    end else begin
        case (state)
            IDLE: ;
            CALC: begin
                outdata <= outdata + in_data1 * in_data2;
            end
        endcase
    end
end


endmodule