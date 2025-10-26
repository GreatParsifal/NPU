
`timescale 1ns/1ps

module accelerator (
    input logic clka,
    input logic wea,
    input logic ena,
    input logic [10:0] addra,
    input logic [31:0] dina,
    output logic [31:0] douta,
    input logic rst_ni
);

    // -----------------------------
    // L/URAM banked memories (8 + 8)
    // -----------------------------
    logic [7:0]        csL;
    logic [5:0]        addressL [7:0];
    wire  [31:0]       qL      [7:0];

    logic [7:0]        csU;
    logic [5:0]        addressU [7:0];
    wire  [31:0]       qU      [7:0];

    // AXI/bus mux
    logic [5:0]        addressL_muxed [7:0];
    logic [7:0][5:0]   addressL_axi;
    logic [7:0]        csL_muxed;
    logic [7:0]        csL_axi;

    logic [5:0]        addressU_muxed [7:0];
    logic [7:0][5:0]   addressU_axi;
    logic [7:0]        csU_muxed;
    logic [7:0]        csU_axi;

    // -----------------------------
    // Bus read data staging
    // -----------------------------
    logic        buffered_ena;
    logic [10:0] buffered_addra;

    // -----------------------------
    // Simple CNN->FCN pipeline control
    // -----------------------------
    logic busy, comp_done;

    // start pulses (one-cycle)
    logic start_cnn_pulse, start_fcn_pulse;

    // result buffer (mapped to 577..1600)
    // 1600-577 = 1023 -> 1024 entries
    logic [31:0] res_buf [0:1023];

    // FCN single output captured to res_buf[0]
    logic [31:0] fcn_out0;

    logic cnn_done, fcn_done;

    // -----------------------------
    // Address Muxing and Read Data Select
    // -----------------------------
    always_comb begin
        // default
        csL_axi       = '0;
        addressL_axi  = '0;
        csU_axi       = '0;
        addressU_axi  = '0;

        // L banks: 0..287
        if (addra < 11'd288) begin
            csL_axi[addra/36] = ena;
        end
        for (int i = 0; i < 8; i++) begin
            addressL_axi[i]   = addra % 36;
            addressL_muxed[i] = ena ? addressL_axi[i] : addressL[i];
            csL_muxed[i]      = ena ? csL_axi[i]      : csL[i];
        end

        // U banks: 288..575
        if (addra >= 11'd288 && addra < 11'd576) begin
            csU_axi[(addra-288)/36] = ena;
        end
        for (int i = 0; i < 8; i++) begin
            addressU_axi[i]   = (addra - 11'd288) % 36;
            addressU_muxed[i] = ena ? addressU_axi[i] : addressU[i];
            csU_muxed[i]      = ena ? csU_axi[i]      : csU[i];
        end

        // Read data MUX (use buffered address/ena because RAM is sync-read)
        douta = 32'd0;
        if (buffered_ena) begin
            if (buffered_addra < 11'd288) begin
                douta = qL[buffered_addra/36];
            end
            else if (buffered_addra >= 11'd288 && buffered_addra < 11'd576) begin
                douta = qU[(buffered_addra-11'd288)/36];
            end
            else if (buffered_addra == 11'd576) begin
                // status: bit0=done, bit1=busy
                douta = {30'd0, busy, comp_done};
            end
            else if (buffered_addra > 11'd576 && buffered_addra <= 11'd1600) begin
                douta = res_buf[buffered_addra - 11'd577];
            end
        end
    end

    // -----------------------------
    // Sequencing and control
    // -----------------------------
    always_ff @(posedge clka) begin
        if (!rst_ni) begin
            // defaults
            for (int i = 0; i < 8; i++) begin
                addressL[i] <= '0;
                addressU[i] <= '0;
            end
            csL <= '0;
            csU <= '0;

            buffered_addra <= '0;
            buffered_ena   <= 1'b0;

            busy       <= 1'b0;
            comp_done  <= 1'b0;
            start_cnn_pulse <= 1'b0;
            start_fcn_pulse <= 1'b0;

            for (int j = 0; j < 1024; j++) begin
                res_buf[j] <= 32'd0;
            end
        end
        else begin
            // stage bus signals for sync-read
            buffered_addra <= addra;
            buffered_ena   <= ena;

            // default deassert start pulses
            start_cnn_pulse <= 1'b0;
            start_fcn_pulse <= 1'b0;

            // host writes control at 576: dina[0]==1 starts a run (if not busy)
            if (wea && ena && addra == 11'd576 && dina[0] && !busy) begin
                busy           <= 1'b1;
                comp_done      <= 1'b0;
                start_cnn_pulse <= 1'b1;
            end

            // CNN done -> start FCN
            if (cnn_done) begin
                start_fcn_pulse <= 1'b1;
            end

            // FCN done -> latch output, set done
            if (fcn_done) begin
                busy      <= 1'b0;
                comp_done <= 1'b1;
                res_buf[0] <= fcn_out0; 
            end
        end
    end

    // -----------------------------
    // RAM instances (8 L + 8 U)
    // -----------------------------
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_0  (.clk(clka), .address(addressL_muxed[0]), .cs(csL_muxed[0]), .web(~wea), .d(dina), .q(qL[0]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_1  (.clk(clka), .address(addressL_muxed[1]), .cs(csL_muxed[1]), .web(~wea), .d(dina), .q(qL[1]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_2  (.clk(clka), .address(addressL_muxed[2]), .cs(csL_muxed[2]), .web(~wea), .d(dina), .q(qL[2]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_3  (.clk(clka), .address(addressL_muxed[3]), .cs(csL_muxed[3]), .web(~wea), .d(dina), .q(qL[3]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_4  (.clk(clka), .address(addressL_muxed[4]), .cs(csL_muxed[4]), .web(~wea), .d(dina), .q(qL[4]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_5  (.clk(clka), .address(addressL_muxed[5]), .cs(csL_muxed[5]), .web(~wea), .d(dina), .q(qL[5]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_6  (.clk(clka), .address(addressL_muxed[6]), .cs(csL_muxed[6]), .web(~wea), .d(dina), .q(qL[6]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_7  (.clk(clka), .address(addressL_muxed[7]), .cs(csL_muxed[7]), .web(~wea), .d(dina), .q(qL[7]));

    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_8  (.clk(clka), .address(addressU_muxed[0]), .cs(csU_muxed[0]), .web(~wea), .d(dina), .q(qU[0]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_9  (.clk(clka), .address(addressU_muxed[1]), .cs(csU_muxed[1]), .web(~wea), .d(dina), .q(qU[1]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_10 (.clk(clka), .address(addressU_muxed[2]), .cs(csU_muxed[2]), .web(~wea), .d(dina), .q(qU[2]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_11 (.clk(clka), .address(addressU_muxed[3]), .cs(csU_muxed[3]), .web(~wea), .d(dina), .q(qU[3]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_12 (.clk(clka), .address(addressU_muxed[4]), .cs(csU_muxed[4]), .web(~wea), .d(dina), .q(qU[4]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_13 (.clk(clka), .address(addressU_muxed[5]), .cs(csU_muxed[5]), .web(~wea), .d(dina), .q(qU[5]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_14 (.clk(clka), .address(addressU_muxed[6]), .cs(csU_muxed[6]), .web(~wea), .d(dina), .q(qU[6]));
    ram #(.DATA_WIDTH(32), .ADDR_WIDTH(6)) ram_instance_15 (.clk(clka), .address(addressU_muxed[7]), .cs(csU_muxed[7]), .web(~wea), .d(dina), .q(qU[7]));

    // -----------------------------
    // CNN / FCN stubs (no-PE compute here)
    // -----------------------------

    cnn_core u_cnn (
        .clk    (clka),
        .rst_ni (rst_ni),
        .start  (start_cnn_pulse),
        .done   (cnn_done)
    );

    fcn_core u_fcn (
        .clk    (clka),
        .rst_ni (rst_ni),
        .start  (start_fcn_pulse),
        .done   (fcn_done),
        .out0   (fcn_out0)
    );

endmodule

//just for test purpose
module cnn_core (
    input  logic clk,
    input  logic rst_ni,
    input  logic start,  
    output logic done    
);
    parameter int LATENCY = 8;

    logic running;
    logic [$clog2(LATENCY):0] cnt;

    always_ff @(posedge clk) begin
        if (!rst_ni) begin
            running <= 1'b0;
            cnt     <= '0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0; // default
            if (start && !running) begin
                running <= 1'b1;
                cnt     <= '0;
            end else if (running) begin
                if (cnt == LATENCY-1) begin
                    running <= 1'b0;
                    done    <= 1'b1; 
                end else begin
                    cnt <= cnt + 1;
                end
            end
        end
    end
endmodule

module fcn_core (
    input  logic clk,
    input  logic rst_ni,
    input  logic start,   
    output logic done,    
    output logic [31:0] out0
);
    parameter int LATENCY   = 4;
    parameter logic [31:0] OUT_CONST = 32'd123; 

    logic running;
    logic [$clog2(LATENCY):0] cnt;

    assign out0 = OUT_CONST;

    always_ff @(posedge clk) begin
        if (!rst_ni) begin
            running <= 1'b0;
            cnt     <= '0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0; 
            if (start && !running) begin
                running <= 1'b1;
                cnt     <= '0;
            end else if (running) begin
                if (cnt == LATENCY-1) begin
                    running <= 1'b0;
                    done    <= 1'b1;
                end else begin
                    cnt <= cnt + 1;
                end
            end
        end
    end
endmodule