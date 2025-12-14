module cir_reg_w # (
    K_H = 3,
    K_W = 3
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  load_en,
    input  logic                  clear,
    input  logic [7:0]     in_data [0:K_H-1],
    output logic [7:0]     out_data1 [0:K_H-1], // positive port
    input logic                   shift
);

    logic [7:0] register [0:K_H-1][0:K_W-1];
    integer i, j;

    // load input data into circular register
    always_ff @(posedge clk) begin
        if (!rst_n || clear) begin
            for (i=0;i<K_H;i=i+1) begin
                for (j=0;j<K_W;j=j+1) begin
                    register[i][j] <= 8'd0;
                end
            end
        end else if (shift) begin
            for (i=K_H-1;i>0;i=i-1) begin
                for (j=K_W-1;j>0;j=j-1) begin
                    register[i][j] <= register[i][j-1];
                end
                register[i][0] <= register[i][K_W-1];
            end
        end else if (load_en) begin
            for (i=K_H-1;i>0;i=i-1) begin
                for (j=K_W-1;j>0;j=j-1) begin
                    register[i][j] <= register[i][j-1];
                end
                register[i][0] <= in_data[i];
            end
        end
    end

    genvar gi;
    generate
        for (gi=0;gi<K_H;gi=gi+1) begin : gen_out_data
            assign out_data1[gi] = register[gi][0];
        end
    endgenerate

endmodule