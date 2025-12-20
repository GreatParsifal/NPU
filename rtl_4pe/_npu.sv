module npu #(
    parameter int K_H = 3,
    parameter int K_W = 3,
    parameter int IN1_H = 16,
    parameter int IN1_W = 15,
    parameter int OUT2_H = 12,
    parameter int OUT2_W = 11,
    parameter int CHAN = 10,
    parameter int IN1_N  = 132,
    parameter int OUT1_M = 10,
    parameter int NUM_PE  = 4
)(
    input  logic        clk,
    input  logic        rst_ni,
    input  logic        ena,
    input  logic        wea,
    input  logic [15:0] addra,
    input  logic [31:0] dina,
    output logic [31:0] douta
);
    wire rst = ~rst_ni;

    localparam int IMG_SIZE = IN1_H*IN1_W;
    localparam int WC_SIZE  = K_H*K_W;
    localparam int FV_LEN   = OUT2_H*OUT2_W;

    //conv layer
    logic [7:0] in_img  [0:K_H-1]; // interface
    logic signed [7:0] img[0:K_H-1][0:K_W-1];
    logic host_img_clear;

    logic signed [7:0] in_conv_w [0:K_H-1];
    logic signed [7:0] conv_w   [0:K_H-1][0:K_W-1];
    logic host_conv_w_clear;

    logic signed [23:0] pe_out[0:K_H-1];
    logic signed [23:0] pe_sum;
    logic host_trigger, pe_ready;

    // fcn layer
    logic [31:0] fcn_in;

    // addra decode
    wire [2:0] sel = addra[14:12];
    logic host_wea;

    // weight and input circular register
    logic img_load_en;
    always_ff @(posedge clk) begin
        if (rst) begin
            img_load_en <= 1'b0;
        end else if (sel == 3'b001 && host_wea) begin
            img_load_en <= 1'b1;
        end else begin
            img_load_en <= 1'b0;
        end
    end
    cir_reg #(K_H, K_W) img_win (
        .clk(clk),
        .rst_n(rst_ni),
        .clear(host_img_clear),
        .load_en(img_load_en),
        .in_data(in_img),
        .register_img(img)
    );

    logic w_load_en;
    always_ff @(posedge clk) begin
        if (rst) begin
            w_load_en <= 1'b0;
        end else if (sel == 3'b010 && host_wea) begin
            w_load_en <= 1'b1;
        end else begin
            w_load_en <= 1'b0;
        end
    end
    cir_reg #(K_H, K_W) w_win (
        .clk(clk),
        .rst_n(rst_ni),
        .clear(host_conv_w_clear),
        .load_en(w_load_en),
        .in_data(in_conv_w),
        .register_w(conv_w)
    );

    // conv win calculation module ( 9 pe )
    logic signed [23:0] conv_out;
    conv_unit #(K_H, K_W) conv_pe (
        .clk(clk),
        .ready(pe_ready),
        .img(img),
        .w(conv_w),
        .result(conv_out)
    )

    // conv output package module
    logic pack_in_valid;
    logic host_pack_clear;
    logic [31:0] conv1_out_pack;
    logic [23:0] result_reg;
    pack conv_out_pack (
        .clk(clk),
        .rst_n(rst_ni),
        .in_valid(pack_in_valid),
        .in_data(result_reg),
        .clear(host_pack_clear),
        .out_data(conv1_out_pack)
    );

    // fcn pe generate
    logic signed [8:0] fcn_in_sel [0:K_H-1];
    logic signed [7:0] fcn_w_sel [0:K_H-1];
    logic host_pe_clear;
    genvar gi;
    generate
        for (gi = 0; gi < K_H; gi = gi + 1) begin : PE_GEN
            pe_unit_fcn pe_fcn (
                .clk(clk),
                .rst_n(rst_ni),
                .clr(host_pe_clear),
                .ready(pe_ready),
                .in_data1(fcn_w_sel[gi]),
                .in_data2(fcn_in_sel[gi]),
                .outdata(pe_out[gi])
            );
        end
    endgenerate

    assign pe_sum = pe_out[0] + pe_out[1] + pe_out[2];

    //control FSM
    typedef enum logic [3:0] {
        S_IDLE,
        S_CONV1_LD,  // load parameters
        S_CONV1_CAL, // calculate
        S_CONV2_LD,
        S_CONV2_CAL,
        S_FCN,
        S_FCN_LAST,
        S_DONE
    }state_e;
    state_e state;

    // pe input selection
    always_comb begin : fcn_pe_sel_logic
        unique case (state)
            S_FCN: begin // 1 input multiplied with weight from 3 channels
                fcn_w_sel[0] = {1'b0, fcn_in[7:0]};
                fcn_w_sel[1] = {1'b0, fcn_in[15:8]};
                fcn_w_sel[2] = {1'b0, fcn_in[23:16]};
                fcn_in_sel[0] = fcn_in[31:24];
                fcn_in_sel[1] = fcn_in[31:24];
                fcn_in_sel[2] = fcn_in[31:24];
            end
            S_FCN_LAST: begin // 2 input multiplied with 2 weights, 5 cycles of calculation are needed for the whole layer
                fcn_in_sel[0] = {1'b0, fcn_in[23:16]};
                fcn_in_sel[1] = {1'b0, fcn_in[31:24]};
                fcn_w_sel[0] = fcn_in[7:0];
                fcn_w_sel[1] = fcn_in[15:8];
            end
            default: begin
                fcn_w_sel[0] = 8'b0;
                fcn_w_sel[1] = 8'b0;
                fcn_w_sel[2] = 8'b0;
                fcn_in_sel[0] = 9'b0;
                fcn_in_sel[1] = 9'b0;
                fcn_in_sel[2] = 9'b0;
            end
        endcase
    end
    
    // main
    logic done_reg;
    logic host_next_state;
    
    // main FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            result_reg <= 24'sd0;
            done_reg <= 1'b0;
        end else begin
            unique case (state)
                S_IDLE: begin
                    state <= S_CONV1_LD;
                end
                S_CONV1_LD: begin
                    pack_in_valid <= 1'b0;
                    if (host_next_state) begin
                        state <= S_CONV2_LD;
                    end else
                    if (host_trigger) begin
                        state <= S_CONV1_CAL;
                        pe_ready <= 1'b1;
                    end
                end
                S_CONV1_CAL: begin
                    result_reg <= conv_out[23] ? 0 : conv_out; // relu
                    // result_reg <= pe_sum; // using for debug
                    state <= S_CONV1_LD;
                    pack_in_valid <= 1'b1;
                end
                S_CONV2_LD: begin
                    pack_in_valid <= 1'b0;        // don't use conv_pack in conv2 calculation
                    if (host_next_state) begin
                        state <= S_FCN;
                    end else
                    if (host_trigger) begin
                        state <= S_CONV2_CAL;
                        pe_ready <= 1'b1;
                    end
                end
                S_CONV2_CAL: begin
                    result_reg <= pe_sum; // no relu
                    state <= S_CONV2_LD;
                end
                S_FCN: begin
                    if (host_trigger) pe_ready <= 1'b1;
                    else pe_ready <= 1'b0;
                    if (host_next_state) begin
                        state <= S_FCN_LAST;
                    end
                end
                S_FCN_LAST: begin
                    if (host_trigger) pe_ready <= 1'b1;
                    else pe_ready <= 1'b0;
                    if (host_next_state) begin
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    done_reg <= 1'b1;
                    state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

    // cpu interface

    assign host_wea = rst ? 1'b0 : (ena & wea);
    logic host_rea;
    assign host_rea = rst ? 1'b0 : (ena & ~wea);
    logic [31:0] result_sel;

    always_comb begin : result_selection
        case(state)
            S_CONV1_LD: result_sel = conv1_out_pack;
            S_CONV1_CAL: result_sel = conv1_out_pack;
            S_CONV1_MINUS: result_sel = conv1_out_pack;
            S_CONV2_LD: result_sel = {{8{result_reg[23]}}, result_reg};            // relu in cpu
            S_CONV2_CAL: result_sel = {{8{result_reg[23]}}, result_reg};
            S_CONV2_MINUS: result_sel = {{8{result_reg[23]}}, result_reg};
            S_FCN: begin
                result_sel[7:0] = pe_out[0][23] ? 8'b0 : pe_out[0][7:0];
                result_sel[15:8] = pe_out[1][23] ? 8'b0 : pe_out[1][15:8];
                result_sel[23:16] = pe_out[2][23] ? 8'b0 : pe_out[2][23:16];
                result_sel[31:24] = 8'b0;
            end
            S_FCN_LAST: result_sel = {{8{pe_sum[23]}}, pe_sum};       // relu in cpu
            default: result_sel = 32'd0;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
        end else if (host_wea) begin
            unique case (sel)
                3'b001: begin
                    in_img[0] <= dina[7:0];
                    in_img[1] <= dina[15:8];
                    in_img[2] <= dina[23:16];
                end
                3'b010: begin
                    in_conv_w[0] <= dina[7:0];
                    in_conv_w[1] <= dina[15:8];
                    in_conv_w[2] <= dina[23:16];
                end
                3'b011: begin
                    fcn_in[7:0] <= dina[7:0];
                    fcn_in[15:8] <= dina[15:8];
                    fcn_in[23:16] <= dina[23:16];
                    fcn_in[31:24] <= dina[31:24];
                end
                3'b100: begin
                    host_trigger <= dina[0];
                    host_next_state <= dina[1];
                    host_pe_clear <= dina[2];
                    host_img_clear <= dina[3];
                    host_conv_w_clear <= dina[4];
                    host_pack_clear <= dina[5];
                end
                default: begin
                end
            endcase
        end
        else if (host_rea) begin
            unique case (sel)
		        3'd5: douta <= {31'd0, done_reg};
                3'd6: douta <= result_sel;
                default: douta <= 32'd0;
            endcase
        end else begin
            host_trigger <= 1'b0;
            host_next_state <= 1'b0;
            host_pe_clear <= 1'b0;
            host_img_clear <= 1'b0;
            host_conv_w_clear <= 1'b0;
            host_pack_clear <= 1'b0;
        end
    end

endmodule