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
    logic signed [8:0] img_pos[0:K_H-1];
    logic signed [8:0] img_neg[0:K_H-1];
    logic host_img_clear;

    logic signed [7:0] in_conv_w [0:K_H-1];
    logic signed [7:0] conv_w   [0:K_H-1];
    logci host_conv_w_clear;
    logic conv_w_shift;

    logic signed [23:0] pe_out[0:K_H-1];
    logic signed [23:0] pe_sum;
    logic host_trigger, minus_trigger;

    // fcn layer
    logic [31:0] fcn_input;

    // addra decode
    wire [2:0] sel = addra[2:0];

    // weight and input circular register
    cir_reg_img #(K_H, K_W) img (
        .clk(clk),
        .rst_n(rst_ni),
        .load_en(sel == 3'b001 && host_wea),
        .in_data(in_img),
        .out_data1(img_pos),
        .out_data2(img_neg)
    );

    cir_reg_w #(K_H, K_W) weight (
        .clk(clk),
        .rst_n(rst_ni),
        .load_en(sel == 3'b010 && host_wea),
        .in_data(in_conv_w),
        .out_data1(conv_w),
        .shift(conv_w_shift)
    );

    // pe generate
    logic signed [8:0] pe_input_sel [0:K_H-1];
    logic signed [7:0] pe_w_sel [0:K_H-1];
    genvar gi;
    generate
        for (gi = 0; gi < K_H; gi = gi + 1) begin : PE_GEN
            pe_unit_fcn pe_conv_inst (
                .clk(clk),
                .rst_n(rst_ni),
                .clear(host_pe_clear),
                .ready(host_trigger||minus_trigger),
                .in_data1(pe_w_sel[gi]),
                .in_data2(pe_input_sel[gi]),
                .outdata(pe_out[gi])
            );
            assign pe_sum += pe_out[gi];
        end
    endgenerate

    //control FSM
    typedef enum logic [2:0] {
        S_IDLE,
        S_CONV1_LD,  // load parameters
        S_CONV1_CAL, // calculate
        S_CONV1_MINUS,
        S_CONV2_LD,
        S_CONV2_CAL,
        S_CONV2_MINUS,
        S_FCN1,
        S_FCN1_LAST,
        S_FCN2,
        S_DONE
    }state_e;
    state_e state;

    // pe input selection
    always_comb begin : pe_sel_logic
        unique case (state)
            S_IDLE: 
            S_CONV1_LD: 
            S_CONV1_CAL: begin
                pe_input_sel = {1'b0, img_pos};
                pe_w_sel = conv_w;
            end
            S_CONV1_MINUS: begin
                pe_input_sel = {1'b1, img_neg};
                pe_w_sel = conv_w;
            end
            S_CONV2_LD: 
            S_CONV2_CAL: begin
                pe_input_sel = {1'b0, img_pos};
                pe_w_sel = conv_w;
            end
            S_CONV2_MINUS: begin
                pe_input_sel = {1'b1, img_neg};
                pe_w_sel = conv_w;
            end
            S_FCN1: begin // 1 input multiplied with weight from 3 channels
                pe_w_sel[0] = {1'b0, fcn_in[7:0]};
                pe_w_sel[1] = {1'b0, fcn_in[15:8]};
                pe_w_sel[2] = {1'b0, fcn_in[23:16]};
                pe_input_sel[0] = fcn_in[31:24];
                pe_input_sel[1] = fcn_in[31:24];
                pe_input_sel[2] = fcn_in[31:24];
            end
            S_FCN1_LAST: begin // 3 input multiplied with weight from 1 channel, pe result is summed up by wine pe_sum
                pe_input_sel[0] = {1'b0, fcn_in[7:0]};
                pe_input_sel[1] = {1'b0, fcn_in[15:8]};
                pe_input_sel[2] = {1'b0, fcn_in[23:16]};
                pe_w_sel[0] = fcn_in[31:24];
                pe_w_sel[1] = fcn_in[31:24];
                pe_w_sel[2] = fcn_in[31:24];
            end
            S_FCN2: begin // 2 input multiplied with 2 weights, 5 cycles of calculation are needed for the whole layer
                pe_input_sel[0] = {1'b0, fcn_in[7:0]};
                pe_input_sel[1] = {1'b0, fcn_in[15:8]};
                pe_w_sel[0] = fcn_in[23:16];
                pe_w_sel[1] = fcn_in[31:24];
            end
            S_DONE: 
        endcase
    end
    
    // main
    logic valid_reg;
    logic done_reg;
    logic [23:0] result_reg;
    logic host_next_state;

    assign host_trigger = (sel == 3'b100) ? dina[0] : 1'b0;
    assign host_next_state = (sel == 3'b100) ? dina[1] : 1'b0;
    assign host_pe_clear = (sel == 3'b100) ? dina[2] : 1'b0;
    assign host_img_clear = (sel == 3'b100) ? dina[3] : 1'b0;
    assign host_conv_w_clear = (sel == 3'b100) ? dina[4] : 1'b0;
    
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
                    w_shift <= 1'b0;
                    if (host_next_state) begin
                        state <= S_CONV2_LD;
                    end else
                    if (host_trigger) begin
                        valid_reg <= 1'b0;
                        state <= S_CONV1_CAL;
                    end
                end
                S_CONV1_CAL: begin
                    result_reg <= (pe_sum[23]) ? 24'sd0 : pe_sum; // relu
                    valid_reg <= 1'b1;
                    state <= S_CONV1_MINUS;
                    minus_trigger <= 1'b1;
                end
                S_CONV1_MINUS: begin
                    minus_trigger <= 1'b0;
                    state <= S_CONV1_LD;
                    w_shift <= 1'b1;
                end
                S_CONV2_LD: begin
                    w_shift <= 1'b0;
                    if (host_next_state) begin
                        state <= S_FCN1;
                    end else
                    if (host_trigger) begin
                        valid_reg <= 1'b0;
                        state <= S_CONV2_CAL;
                    end
                end
                S_CONV2_CAL: begin
                    result_reg <= pe_sum; // no relu
                    valid_reg <= 1'b1;
                    state <= S_CONV2_MINUS;
                    minus_trigger <= 1'b1;
                end
                S_CONV2_MINUS: begin
                    minus_trigger <= 1'b0;
                    state <= S_CONV2_LD;
                    w_shift <= 1'b1;
                end
                S_FCN1: begin
                    if (host_next_state) begin
                        state <= S_FCN1_LAST;
                    end
                end
                S_FCN1_LAST: begin
                    if (host_next_state) begin
                        state <= S_FCN2;
                    end
                end
                S_FCN2: begin
                    if (host_next_state) begin
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    done_reg <= 1'b1;
                    state <= S_IDLE;
                end
                
                default: ;
            endcase
        end
    end

    // cpu interface

    logic host_wea;
    assign host_wea = rst ? 1'b0 : (ena & wea);
    logic host_rea;
    assign host_rea = rst ? 1'b0 : (ena & ~wea);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            host_img_clear <= 1'b1;
            host_pe_clear <= 1'b1;
            host_conv_w_clear <= 1'b1;
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
                    // trigger and clear signals
                end
                default: ;
            endcase
        end
        else if (host_rea) begin
            unique case (sel)
		        3'd1: douta <= {31'd0, done_reg};
                3'd2: douta <= {24'b0, result_reg};
                3'd3: douta <= {31'd0, pixel_valid};
                3'd4: douta <= {23'b0, conv2_out_pixel};
                default: douta <= 32'd0;
            endcase
        end
    end

endmodule