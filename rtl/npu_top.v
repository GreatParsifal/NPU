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
`include "fc1.v"
`include "fc_layer2.v"

module npu_top #(
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
    // States
    localparam S_IDLE = 3'd0,
               S_C1   = 3'd1,
               S_C2   = 3'd2,
               S_FC1  = 3'd3,
               S_FC2  = 3'd4,
               S_DONE = 3'd5;

    reg [2:0] state;

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

    // fc1: 132->10
    wire signed [7:0] fc1_out_w [0:9];
    wire done_fc1;

    // fc2: 10->1
    wire done_fc2;
    wire signed [23:0] fc2_res;

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

    fc1 u_fc1 (
        .clk(clk), .rst(rst), .start(start_fc1),
        .in_vec(conv2_out_w), .weights(w_fc1),
        .done(done_fc1), .out_vec(fc1_out_w)
    );

    fc_layer2_systolic u_fc2 (
        .clk(clk), .rst(rst), .start(start_fc2),
        .input_vec(fc1_out_w), .weight_vec(w_fc2),
        .done(done_fc2), .result(fc2_res)
    );

    //addr decoding and data writing
    wire [2:0] sel = addr[14:12];
    wire [11:0] idx = addr[11:0];

    always @(posedge clk) begin
        if (rst) begin
            
        end else if (en) begin
        case(sel)
            3'b000: if (en) img_in[idx] <= w_data[7:0]; // input image
            3'b001: if (en) w_conv1[idx] <= w_data[7:0]; // conv1 weights
            3'b010: if (en) w_conv2[idx] <= w_data[7:0]; // conv2 weights
            3'b011: if (en) w_fc1[idx]   <= w_data[7:0]; // fc1 weights
            3'b100: if (en) w_fc2[idx]   <= w_data[7:0]; // fc2 weights
            3'b101: begin
                case(idx)
                    12'd0: if (en) begin
                        start_c1 <= 1'b0;
                        start_c2 <= 1'b0;
                        start_fc1 <= 1'b0;
                        start_fc2 <= 1'b0;
                    end
                    12'd1: begin
                        start_c1 <= 1'b1; // trigger start
                    end
                    12'd2: begin
                        // require output logic if needed
                    end
                    default: ;
                endcase
            end else begin
                start_c1 <= 1'b0;
                start_c2 <= 1'b0;
                start_fc1 <= 1'b0;
                start_fc2 <= 1'b0;
            end
        endcase
        end
    end
                    
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; done <= 1'b0; out <= 24'sd0;
            start_c1 <= 1'b0; start_c2 <= 1'b0; start_fc1 <= 1'b0; start_fc2 <= 1'b0;
        end else begin
            // default strobes low
            start_c1 <= 1'b0; start_c2 <= 1'b0; start_fc1 <= 1'b0; start_fc2 <= 1'b0;
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        start_c1 <= 1'b1;
                        state <= S_C1;
                    end
                end
                S_C1: begin
                    if (done_c1) begin
                        start_c2 <= 1'b1;
                        state <= S_C2;
                    end
                end
                S_C2: begin
                    if (done_c2) begin
                        start_fc1 <= 1'b1;
                        state <= S_FC1;
                    end
                end
                S_FC1: begin
                    if (done_fc1) begin
                        start_fc2 <= 1'b1;
                        state <= S_FC2;
                    end
                end
                S_FC2: begin
                    if (done_fc2) begin
                        out <= fc2_res;
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    done <= 1'b1;
                    if (!en) state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
