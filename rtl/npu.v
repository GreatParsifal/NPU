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
`include "conv1.v"
`include "conv2.v"
`include "fcn.v"

module npu #(
    // Dimension limits
    parameter IN1_H = 16,
    parameter IN1_W = 15
)(
    input wire clk,
    input wire rst,
    input wire en, //enable signal
    input wire [14:0] addr,
    input wire [31:0] r_data,
    input wire [31:0] w_data
);

    //buffers and sizes
    localparam int IMG_SIZE  = IN1_H*IN1_W;     // 16*15 = 240
    localparam int WC1_SIZE  = 3*3*10;          // 90
    localparam int WC2_SIZE  = 3*3*10;          // 90
    localparam int WF1_SIZE  = 132*10;          // 1320
    localparam int WF2_SIZE  = 10;              // 10

    reg [7:0] img_in [0:IMG_SIZE-1];                       // 16x15
    reg signed [7:0] w_conv1 [0:WC1_SIZE-1];               // 3x3x1x10
    reg signed [7:0] w_conv2 [0:WC2_SIZE-1];               // 3x3x10x1
    reg signed [7:0] w_fc1 [0:WF1_SIZE-1];                 // 132x10
    reg signed [7:0] w_fc2 [0:WF2_SIZE-1];                 // 10x1

    // Buffers between stages
    // conv1: 14x13x10 = 1820
    wire signed [7:0] conv1_out_w [0:(16-3+1)*(15-3+1)*10-1];
    wire done_c1;

    // conv2: 12x11x1 = 132
    wire signed [7:0] conv2_out_w [0:(14-3+1)*(13-3+1)-1];
    wire done_c2;

    // fcn (FC1+FC2 合并)
    // 来自 conv2 的 132 维输入向量
    wire  signed [7:0] in_vec_array [0:132-1];
    // FC1 权重二维数组（神经元主序 [neuron][k]）
    wire  signed [7:0] fc1_w_array [0:10-1][0:132-1];
    // FC2 权重一维数组
    wire  signed [7:0] fc2_w_array [0:10-1];

    // 
    genvar gi, gj;
    generate
        for (gi = 0; gi < 132; gi = gi + 1) begin : GEN_IN_VEC
            assign in_vec_array[gi] = conv2_out_w[gi];
        end
        for (gi = 0; gi < 10; gi = gi + 1) begin : GEN_W_FC1_ROW
            for (gj = 0; gj < 132; gj = gj + 1) begin : GEN_W_FC1_COL
                assign fc1_w_array[gi][gj] = w_fc1[gi*132 + gj];
            end
            assign fc2_w_array[gi] = w_fc2[gi];
        end
    endgenerate

    // Stage start strobes
    reg start_c1, start_c2, start_fc1, start_fc2;

    conv1 u_c1 (
        .clk(clk), .rst(rst), .start(start_c1),
        .in_img(img_in), .weights(w_conv1),
        .done(done_c1), .out_feat(conv1_out_w)
    );

    conv2 u_c2 (
        .clk(clk), .rst(rst), .start(start_c2),
        .in_feat(conv1_out_w), .weights(w_conv2),
        .done(done_c2), .out_feat(conv2_out_w)
    );

    // FCN 控制脉冲
    reg in_vec_wr;
    reg fc1_w_wr_all;
    reg fc2_w_wr_all;
    reg fcn_start;
    wire fcn_done;
    wire signed [23:0] fcn_logit;

    // 实例化 fcn（使用并行数组一次性写入接口）
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

    //addr decoding and data writing
    wire [2:0] sel = addr[14:12];
    wire [11:0] idx = addr[11:0];

    // 控制寄存器：通过 addr=101:1 触发一次完整流水
    reg ctrl_start;

    always @(posedge clk) begin
        if (rst) begin
            ctrl_start <= 1'b0;
        end else if (en) begin
        case(sel)
            3'b000: if (en) img_in[idx] <= w_data[7:0]; // input image
            3'b001: if (en) w_conv1[idx] <= w_data[7:0]; // conv1 weights
            3'b010: if (en) w_conv2[idx] <= w_data[7:0]; // conv2 weights
            3'b011: if (en) w_fc1[idx]   <= w_data[7:0]; // fc1 weights
            3'b100: if (en) w_fc2[idx]   <= w_data[7:0]; // fc2 weights
            3'b101: begin
                case(idx)
                    12'd0: if (en) ctrl_start <= 1'b0; // rst control flags only
                    12'd1: ctrl_start <= 1'b1;         // trigger start pulse (由状态机消费并清零)
                    12'd2: begin
                        // require output logic if needed
                    end
                    default: ;
                endcase
            end
        endcase
        end
    end
                    
    // 装载/计算状态机：conv1 -> conv2 -> 一拍装载 fcn -> 运行 fcn
    localparam P_IDLE       = 4'd0,
               P_C1         = 4'd1,
               P_C2         = 4'd2,
               P_LOAD_FC1W  = 4'd3,
               P_LOAD_FC2W  = 4'd4,
               P_LOAD_IN    = 4'd5,
               P_FCN_START  = 4'd6,
               P_FCN_WAIT   = 4'd7,
               P_DONE       = 4'd8;

    reg [3:0] p_state;
    reg signed [23:0] result_logit;

    always @(posedge clk) begin
        if (rst) begin
            p_state      <= P_IDLE;
            start_c1     <= 1'b0;
            start_c2     <= 1'b0;
            in_vec_wr    <= 1'b0;
            fc1_w_wr_all <= 1'b0;
            fc2_w_wr_all <= 1'b0;
            fcn_start    <= 1'b0;
            result_logit <= 24'sd0;
        end else begin
            // 默认拉低一次性脉冲
            start_c1     <= 1'b0;
            start_c2     <= 1'b0;
            in_vec_wr    <= 1'b0;
            fc1_w_wr_all <= 1'b0;
            fc2_w_wr_all <= 1'b0;
            fcn_start    <= 1'b0;

            case (p_state)
                P_IDLE: begin
                    if (ctrl_start) begin
                        start_c1 <= 1'b1;  // 触发 conv1
                        p_state  <= P_C1;
                        // 消费触发
                        ctrl_start <= 1'b0;
                    end
                end
                P_C1: begin
                    if (done_c1) begin
                        start_c2 <= 1'b1;  // 触发 conv2
                        p_state  <= P_C2;
                    end
                end
                P_C2: begin
                    if (done_c2) begin
                        // 一拍装载 FC1 权重
                        fc1_w_wr_all <= 1'b1;
                        p_state      <= P_LOAD_FC2W;
                    end
                end
                P_LOAD_FC2W: begin
                    // 紧接着一拍装载 FC2 权重
                    fc2_w_wr_all <= 1'b1;
                    p_state      <= P_LOAD_IN;
                end
                P_LOAD_IN: begin
                    // 一拍装载输入向量
                    in_vec_wr <= 1'b1;
                    p_state   <= P_FCN_START;
                end
                P_FCN_START: begin
                    fcn_start <= 1'b1;  // 发起 FCN 计算
                    p_state   <= P_FCN_WAIT;
                end
                P_FCN_WAIT: begin
                    if (fcn_done) begin
                        result_logit <= fcn_logit;
                        p_state      <= P_DONE;
                    end
                end
                P_DONE: begin
                    // 保持结果，等待下一次 ctrl_start
                    if (ctrl_start) begin
                        start_c1 <= 1'b1;
                        p_state  <= P_C1;
                        ctrl_start <= 1'b0;
                    end
                end
                default: p_state <= P_IDLE;
            endcase
        end
    end
endmodule
