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
    logic signed [7:0] img_pos[0:K_H-1];
    logic signed [7:0] img_neg[0:K_H-1];
    logic host_img_clear;

    logic signed [7:0] in_conv_w [0:K_H-1];
    logic signed [7:0] conv_w   [0:K_H-1];
    logic host_conv_w_clear;
    logic w_shift;

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
    cir_reg_img #(K_H, K_W) img (
        .clk(clk),
        .rst_n(rst_ni),
        .clear(host_img_clear),
        .load_en(img_load_en),
        .in_data(in_img),
        .out_data1(img_pos),
        .out_data2(img_neg)
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
    cir_reg_w #(K_H, K_W) weight (
        .clk(clk),
        .rst_n(rst_ni),
        .clear(host_conv_w_clear),
        .load_en(w_load_en),
        .in_data(in_conv_w),
        .out_data1(conv_w),
        .shift(w_shift)
    );

    // conv output package module
    logic valid_reg;
    logic pack_valid;
    logic host_pack_clear;
    logic [31:0] conv1_out_pack;
    logic [23:0] result_reg;
    pack conv_out_pack (
        .clk(clk),
        .rst_n(rst_ni),
        .in_valid(pack_valid),
        .in_data(result_reg),
        .clear(host_pack_clear),
        .out_data(conv1_out_pack)
    );

    // pe generate
    logic signed [8:0] pe_input_sel [0:K_H-1];
    logic signed [7:0] pe_w_sel [0:K_H-1];
    logic host_pe_clear;
    genvar gi;
    generate
        for (gi = 0; gi < K_H; gi = gi + 1) begin : PE_GEN
            pe_unit_fcn pe_conv_inst (
                .clk(clk),
                .rst_n(rst_ni),
                .clr(host_pe_clear),
                .ready(pe_ready),
                .in_data1(pe_w_sel[gi]),
                .in_data2(pe_input_sel[gi]),
                .outdata(pe_out[gi])
            );
        end
    endgenerate

    assign pe_sum = pe_out[0] + pe_out[1] + pe_out[2];

    //control FSM
    typedef enum logic [3:0] {
        S_IDLE,
        S_CONV1_LD,  // load parameters
        S_CONV1_PRE_CAL1, // first and second cycle for the first conv_win
        S_CONV1_PRE_CAL2,
        S_CONV1_CAL, // calculate
        S_CONV1_MINUS,
        S_CONV2_LD,
        S_CONV2_PRE_CAL1,
        S_CONV2_PRE_CAL2,
        S_CONV2_CAL,
        S_CONV2_MINUS,
        S_FCN,
        S_FCN_LAST,
        S_DONE
    }state_e;
    state_e state;

    // pe input selection
    always_comb begin : pe_sel_logic
        unique case (state)
            S_CONV1_CAL: begin
                pe_input_sel[0] = {1'b0, img_pos[0]};
                pe_input_sel[1] = {1'b0, img_pos[1]};
                pe_input_sel[2] = {1'b0, img_pos[2]};
                pe_w_sel = conv_w;
            end
            S_CONV1_MINUS: begin
                pe_input_sel[0] = ~{1'b0, img_neg[0]}+1'b1;
                pe_input_sel[1] = ~{1'b0, img_neg[1]}+1'b1;
                pe_input_sel[2] = ~{1'b0, img_neg[2]}+1'b1;
                pe_w_sel = conv_w;
            end
            S_CONV2_CAL: begin
                pe_input_sel[0] = {1'b0, img_pos[0]};
                pe_input_sel[1] = {1'b0, img_pos[1]};
                pe_input_sel[2] = {1'b0, img_pos[2]};
                pe_w_sel = conv_w;
            end
            S_CONV2_MINUS: begin
                pe_input_sel[0] = ~{1'b0, img_neg[0]}+1'b1;
                pe_input_sel[1] = ~{1'b0, img_neg[1]}+1'b1;
                pe_input_sel[2] = ~{1'b0, img_neg[2]}+1'b1;
                pe_w_sel = conv_w;
            end
            S_FCN: begin // 1 input multiplied with weight from 3 channels
                pe_w_sel[0] = {1'b0, fcn_in[7:0]};
                pe_w_sel[1] = {1'b0, fcn_in[15:8]};
                pe_w_sel[2] = {1'b0, fcn_in[23:16]};
                pe_input_sel[0] = fcn_in[31:24];
                pe_input_sel[1] = fcn_in[31:24];
                pe_input_sel[2] = fcn_in[31:24];
            end
            S_FCN_LAST: begin // 2 input multiplied with 2 weights, 5 cycles of calculation are needed for the whole layer
                pe_input_sel[0] = {1'b0, fcn_in[7:0]};
                pe_input_sel[1] = {1'b0, fcn_in[15:8]};
                pe_w_sel[0] = fcn_in[23:16];
                pe_w_sel[1] = fcn_in[31:24];
            end
            default: begin
                pe_w_sel[0] = 8'b0;
                pe_w_sel[1] = 8'b0;
                pe_w_sel[2] = 8'b0;
                pe_input_sel[0] = 9'b0;
                pe_input_sel[1] = 9'b0;
                pe_input_sel[2] = 9'b0;
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
            valid_reg <= 1'b0;
            result_reg <= 24'sd0;
            done_reg <= 1'b0;
            w_shift <= 0;
        end else begin
            unique case (state)
                S_IDLE: begin
                    state <= S_CONV1_LD;
                end
                S_CONV1_LD: begin
                    if (host_next_state) begin
                        state <= S_CONV2_LD;
                    end else
                    if (host_trigger) begin
                        valid_reg <= 1'b0;
                        state <= S_CONV1_CAL;
                        w_shift <= 1'b1;
                        pe_ready <= 1'b1;
                    end
                end
                S_CONV1_CAL: begin
                    // result_reg <= (pe_sum[23]) ? 24'sd0 : pe_sum; // relu
                    result_reg <= pe_sum; // using for debug
                    valid_reg <= 1'b1;
                    state <= S_CONV1_MINUS;
                    pe_ready <= 1'b1;
                    w_shift <= 1'b0;
                    pack_valid <= 1'b1;
                end
                S_CONV1_MINUS: begin
                    pe_ready <= 1'b0;
                    pack_valid <= 1'b0;
                    state <= S_CONV1_LD;
                end
                S_CONV2_LD: begin
                    if (host_next_state) begin
                        state <= S_FCN;
                    end else
                    if (host_trigger) begin
                        valid_reg <= 1'b0;
                        state <= S_CONV2_CAL;
                        w_shift <= 1'b1;
                        pe_ready <= 1'b1;
                    end
                end
                S_CONV2_CAL: begin
                    result_reg <= pe_sum; // no relu
                    valid_reg <= 1'b1;
                    state <= S_CONV2_MINUS;
                    pe_ready <= 1'b1;
                    w_shift <= 1'b0;
                    pack_valid <= 1'b1;
                end
                S_CONV2_MINUS: begin
                    pack_valid <= 1'b0;
                    pe_ready <= 1'b0;
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
            S_CONV2_LD: result_sel = {{8{result_reg[23]}}, result_reg};
            S_CONV2_CAL: result_sel = {{8{result_reg[23]}}, result_reg};
            S_CONV2_MINUS: result_sel = {{8{result_reg[23]}}, result_reg};
            S_FCN: begin
                result_sel[7:0] = pe_out[0][23] ? 8'b0 : pe_out[0][7:0];
                result_sel[15:8] = pe_out[0][23] ? 8'b0 : pe_out[0][15:8];
                result_sel[23:16] = pe_out[0][23] ? 8'b0 : pe_out[0][23:16];
                result_sel[31:24] = 8'b0;
            end
            S_FCN_LAST: result_sel = pe_sum[23] ? 32'b0 : {24'b0, pe_sum[7:0]};
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
                3'd7: douta <= {31'd0, valid_reg};
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