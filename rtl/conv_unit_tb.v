module conv_unit_tb;

    parameter K_H = 3;
    parameter K_W = 3;

    // signals
    reg [7:0] conv_win [0:K_H-1][0:K_W-1];
    reg signed [7:0] w [0:K_H-1][0:K_W-1];
    wire signed [23:0] result;
    reg signed [23:0] gt;

    // instantiate DUT
    conv_unit #(
        .K_H(K_H),
        .K_W(K_W)
    ) dut (
        .conv_win(conv_win),
        .w(w),
        .result(result)
    );

    integer i,j;

    // testbench
    initial begin
        gt = 24'b0;
        // initialize inputs
        for (i=0;i<K_H;i=i+1) begin
            for (j=0;j<K_W;j=j+1) begin
                conv_win[i][j] = $random(); // example values
                w[i][j] = $random(); // example weights
                gt = gt + $signed({1'b0, conv_win[i][j]}) * $signed(w[i][j]);
            end
        end

        // wait for a moment
        #10;

        // display result
        $display("Convolution Result: %d", result);
        $display("Golden Model Result: %d", gt);

        // finish simulation
        #10;
        $finish;
    end

    initial begin
        $fsdbDumpfile("conv_unit_tb.fsdb");
        $fsdbDumpvars(0, conv_unit_tb);
        $fsdbDumpMDA();
    end

endmodule