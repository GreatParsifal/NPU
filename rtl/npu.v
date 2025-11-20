//======================================================================
// Module: npu_top
// Description:
//   High-level pipeline wiring conv1 -> conv2 -> fc1 -> fc2 (from README).
//   This is a simple sequential controller that triggers each stage one by one.
// !! IMPORTANT !!
// address definition:
// port name: addr
// width: 3 + 12 = 15
// addr[14:12] defines the state of npu
//     000: receiving input image
//     001: receiving w_conv1 (3*3*10 channel)
//     010: receiving w_conv2 (3*3*10)
//     011: receiving w_fcn1 (132*10)
//     100: receiving w_fcn2 (10*1)
//     101: other operations (trigger, rst, require ...)
// addr[11:0] represents:
//     address of weight or iamge pixel when addr[14:12] < 3'b101;
//     type of operation when addr[14:12] == 3'b101.
//         12'd0: rst
//         12'd1: trigger
//         12'd2: require
//======================================================================
`timescale 1ns/1ps
`include "conv.v"
`include "fcn.v"

module npu #(
    // Dimension limits
    K_H = 3,
    K_W = 3,
    IN1_H = 16,
    IN1_W = 15,
    OUT1_H = 14,
    OUT1_W = 13,
    OUT2_H = 12,
    OUT2_W = 11,
    CHAN = 10
)(
    input logic clk,
    input logic rst_ni,
    input logic ena,
    input logic wea,
    input logic [15:0] addra,
    input logic [31:0] dina,
    input logic [31:0] douta
);

    wire rst = ~rst_ni;
    
    localparam int IMG_SIZE = INCONV_H*INCONV_W;   // 240
    localparam int WC_SIZE  = 3*3*CHAN;            // 90
    localparam int FV_LEN   = OUTCONV_H*OUTCONV_W; // 132
    localparam int FC1_WLEN = FV_LEN*CHAN;         // 132*10 = 1320
    localparam int FC2_WLEN = CHAN;                // 10

    logic                conv_start, conv_done;
    logic signed [7:0]   conv_out  [0:FV_LEN-1];   // 132

    conv u_conv (
        .clk       (clk),
        .rst_n     (~rst),
        .trigger   (conv_start),
        .in_img    (img_in),
        .w_conv1   (w_conv1),
        .w_conv2   (w_conv2),
        .out_buff  (conv_out),
        .out_valid (conv_done)
    );

    logic  signed [7:0] in_vec_array [0:FV_LEN-1];
    logic  signed [7:0] fc1_w_array  [0:CHAN-1][0:FV_LEN-1];
    logic  signed [7:0] fc2_w_array  [0:CHAN-1];
    logic  signed [7:0] img_in       [0:IN1_H-1][0:IN1_W-1];
    logic  signed [7:0] w_conv1      [0:K_H-1][0:K_W-1][0:CHAN-1];
    logic  signed [7:0] w_conv2      [0:K_H-1][0:K_W-1][0:CHAN-1];
    logic  signed [7:0] conv_out     [0:OUT2_H-1][0:OUT2_W-1];

    genvar gi, gj;
    generate
        for (gi = 0; gi < FV_LEN; gi++) begin : GEN_INVEC
            assign in_vec_array[gi] = conv_out[gi];
        end
        for (gi = 0; gi < CHAN; gi++) begin : GEN_FC_W
            assign fc2_w_array[gi] = w_fc2[gi];
            for (gj = 0; gj < FV_LEN; gj++) begin : GEN_FC1_W
                assign fc1_w_array[gi][gj] = w_fc1[gi*FV_LEN + gj];
            end
        end
    endgenerate

    logic in_vec_wr, fc1_w_wr_all, fc2_w_wr_all, fcn_start, fcn_done;
    logic signed [23:0] fcn_logit;

    fcn u_fcn (
        .clk            (clk),
        .rst_n          (~rst),
        .in_vec_wr      (in_vec_wr),
        .in_vec_array   (in_vec_array),
        .fc1_w_wr_all   (fc1_w_wr_all),
        .fc1_w_array    (fc1_w_array),
        .fc2_w_wr_all   (fc2_w_wr_all),
        .fc2_w_array    (fc2_w_array),
        .start          (fcn_start),
        .done           (fcn_done),
        .fc2_logit      (fcn_logit)
    );

    wire [2:0]  sel = addr[14:12];
    wire [11:0] idx = addr[11:0];

    logic ctrl_start;

    always_ff @(posedge clk or posedge rst) begin
       if (ena && wea) begin
            unique case (sel)
                3'b000: begin
                    if (idx < IN1_N/4) begin
                        in_vec[idx*4 + 0] <= dina[7:0];
                        in_vec[idx*4 + 1] <= dina[15:8];
                        in_vec[idx*4 + 2] <= dina[23:16];
                        in_vec[idx*4 + 3] <= dina[31:24];
                    end
                end
                3'b011: begin // fc1_w linear -> flat array                  
                    if (idx*4 < FC1_TOTAL) begin
                        if (idx*4 + 0 < FC1_TOTAL) fc1_w_flat[idx*4 + 0] <= dina[7:0];
                        if (idx*4 + 1 < FC1_TOTAL) fc1_w_flat[idx*4 + 1] <= dina[15:8];
                        if (idx*4 + 2 < FC1_TOTAL) fc1_w_flat[idx*4 + 2] <= dina[23:16];
                        if (idx*4 + 3 < FC1_TOTAL) fc1_w_flat[idx*4 + 3] <= dina[31:24];
                    end
                end
                3'b100: begin
                    
                    if (idx*4 < OUT1_M) begin
                        if (idx*4 + 0 < OUT1_M) fc2_w[idx*4 + 0] <= dina[7:0];
                        if (idx*4 + 1 < OUT1_M) fc2_w[idx*4 + 1] <= dina[15:8];
                        if (idx*4 + 2 < OUT1_M) fc2_w[idx*4 + 2] <= dina[23:16];
                        if (idx*4 + 3 < OUT1_M) fc2_w[idx*4 + 3] <= dina[31:24];
                    end
                end
                3'b101: begin
                    if (idx == 12'd1) ctrl_start <= 1'b1; // trigger
                end
                default: ;
            endcase
        end
        if(state == S_RUN_CONV) begin
            ctrl_start <= 1'b0;
        end
    end
    typedef enum logic [2:0] {
        S_IDLE, S_RUN_CONV, S_LOAD_ALL, S_FCN_START, S_FCN_WAIT, S_DONE
    }state_e;

    state_e st;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            st            <= S_IDLE;
            conv_start    <= 1'b0;
            in_vec_wr     <= 1'b0;
            fc1_w_wr_all  <= 1'b0;
            fc2_w_wr_all  <= 1'b0;
            fcn_start     <= 1'b0;
        end else begin
      
        conv_start    <= 1'b0;
        in_vec_wr     <= 1'b0;
        fc1_w_wr_all  <= 1'b0;
        fc2_w_wr_all  <= 1'b0;
        fcn_start     <= 1'b0;

        unique case (st)
          S_IDLE: if (ctrl_start) begin
            conv_start <= 1'b1;     // 触发 conv
            st         <= S_RUN_CONV;
            ctrl_start <= 1'b0;     
        end
          S_RUN_CONV: if (conv_done) begin
            in_vec_wr     <= 1'b1;
            fc1_w_wr_all  <= 1'b1;
            fc2_w_wr_all  <= 1'b1;
            st            <= S_LOAD_ALL;
        end
          S_LOAD_ALL: begin
            fcn_start <= 1'b1;      // 下一拍启动 fcn
            st            <= S_FCN_WAIT;
        end
        S_FCN_WAIT: if (fcn_done) begin
            st <= S_DONE;
        end
        S_DONE: if(~we)begin
          douta <= {8'sd0, fcn_logit};
          st <= S_IDLE;
        end
        default: st <= S_IDLE;
      endcase
    end
  end
endmodule
