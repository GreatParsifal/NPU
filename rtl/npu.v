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
    CHAN = 10,
    IN1_N  = 132,
    OUT1_M = 10
)(
    input logic clk,
    input logic rst_ni,
    input logic ena,
    input logic wea,
    input logic [15:0] addra,
    input logic [31:0] dina,
    output logic [31:0] douta
);

    wire rst = ~rst_ni;
    
    localparam int IMG_SIZE = IN1_H*IN1_W;   // 240
    localparam int WC_SIZE  = 3*3*CHAN;            // 90
    localparam int FV_LEN   = OUT2_H*OUT2_W; // 132
    localparam int FC1_TOTAL = FV_LEN*CHAN;         // 132*10 = 1320
    localparam int FC2_WLEN = CHAN;                // 10

    logic                conv_start, conv_done;

    

    logic         [7:0] in_vec_array [0:IN1_N-1];
    logic  signed [7:0] fc1_w_array  [0:OUT1_M-1][0:IN1_N-1];
    logic  signed [7:0] fc2_w_array  [0:OUT1_M-1];
    logic         [7:0] img_in       [0:IN1_H-1][0:IN1_W-1];
    logic  signed [7:0] w_conv1      [0:K_H-1][0:K_W-1][0:CHAN-1];
    logic  signed [7:0] w_conv2      [0:K_H-1][0:K_W-1][0:CHAN-1];
    logic         [23:0] conv_out     [0:OUT2_H-1][0:OUT2_W-1];

    logic  signed [7:0] fc1_w_flat   [0:FC1_TOTAL-1]; // 1320
    logic  signed [7:0] fc2_w        [0:OUT1_M-1];
    logic         [7:0] img_in_flat  [0:IMG_SIZE-1];
    logic         [7:0] w_conv1_flat [0:WC_SIZE-1];
    logic         [7:0] w_conv2_flat [0:WC_SIZE-1];



    genvar gi, gj, gk;
    generate
        for (gi = 0; gi < IN1_H; gi++) begin : GEN_IMG_H
            for (gj = 0; gj < IN1_W; gj++) begin : GEN_IMG_W
                assign img_in[gi][gj] = img_in_flat[gi*IN1_W + gj];
            end
        end
        for (gk = 0; gk < CHAN; gk++) begin : GEN_WC1_CHAN
            for (gi = 0; gi < K_H; gi++) begin : GEN_WC1_H
                for (gj = 0; gj < K_W; gj++) begin : GEN_WC1_W
                    assign w_conv1[gi][gj][gk] = w_conv1_flat[gk*K_H*K_W + gi*K_W + gj];
                end
            end
        end
        for (gk = 0; gk < CHAN; gk++) begin : GEN_WC2_CHAN
            for (gi = 0; gi < K_H; gi++) begin : GEN_WC2_H
                for (gj = 0; gj < K_W; gj++) begin : GEN_WC2_W
                    assign w_conv2[gi][gj][gk] = w_conv2_flat[gk*K_H*K_W + gi*K_W + gj];
                end
            end
        end
        for (gi = 0; gi < OUT2_H; gi++) begin : GEN_INVEC
            for (gj = 0; gj < OUT2_W; gj++) begin : GEN_INVEC_W
                assign in_vec_array[gi*OUT2_W + gj] = conv_out[gi][gj][7:0];
            end
        end
        for (gi = 0; gi < CHAN; gi++) begin : GEN_FC_W
            assign fc2_w_array[gi] = fc2_w[gi];
            for (gj = 0; gj < FV_LEN; gj++) begin : GEN_FC1_W
                assign fc1_w_array[gi][gj] = fc1_w_flat[gi*FV_LEN + gj];
            end
        end
    endgenerate

    logic in_vec_wr, fc1_w_wr_all, fc2_w_wr_all, fcn_start, fcn_done;
    logic signed [23:0] fcn_logit;

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

    wire [2:0]  sel = addra[14:12];
    wire [11:0] idx = addra[11:0];

    logic ctrl_start;

    typedef enum logic [3:0] {
        S_IDLE,
        S_CONV_WAIT,
        S_CONV_DONE,
	    S_FCN_WAIT,
        S_DONE
    } state_e;


    state_e state;

    always @(*) begin
       if (ena && wea) begin
            unique case (sel)
                3'b110: begin
                    if(idx*4 < IMG_SIZE) begin
                        if (idx*4 + 0 < IMG_SIZE) img_in_flat[idx*4 + 0] <= dina[7:0];
                        if (idx*4 + 1 < IMG_SIZE) img_in_flat[idx*4 + 1] <= dina[15:8];
                        if (idx*4 + 2 < IMG_SIZE) img_in_flat[idx*4 + 2] <= dina[23:16];
                        if (idx*4 + 3 < IMG_SIZE) img_in_flat[idx*4 + 3] <= dina[31:24];
                    end
                end
                3'b001: begin
                    if(idx*4 < WC_SIZE) begin
                        if (idx*4 + 0 < WC_SIZE) w_conv1_flat[idx*4 + 0] <= dina[7:0];
                        if (idx*4 + 1 < WC_SIZE) w_conv1_flat[idx*4 + 1] <= dina[15:8];
                        if (idx*4 + 2 < WC_SIZE) w_conv1_flat[idx*4 + 2] <= dina[23:16];
                        if (idx*4 + 3 < WC_SIZE) w_conv1_flat[idx*4 + 3] <= dina[31:24];
                    end
                end
                3'b010: begin
                    if(idx*4 < WC_SIZE) begin
                        if (idx*4 + 0 < WC_SIZE) w_conv2_flat[idx*4 + 0] <= dina[7:0];
                        if (idx*4 + 1 < WC_SIZE) w_conv2_flat[idx*4 + 1] <= dina[15:8];
                        if (idx*4 + 2 < WC_SIZE) w_conv2_flat[idx*4 + 2] <= dina[23:16];
                        if (idx*4 + 3 < WC_SIZE) w_conv2_flat[idx*4 + 3] <= dina[31:24];
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
        if(state == S_CONV_WAIT) begin
            ctrl_start <= 1'b0;
        end
    end
    

    logic        done_reg;
    logic signed [23:0] result_reg;

    logic        clr_all, ready_all;
    logic signed [7:0]  current_x;
    logic signed [7:0]  w_bus      [0:CHAN-1];
    logic signed [23:0] pe_out     [0:CHAN-1];
    logic signed [23:0] fc1_out_relu [0:CHAN-1];
    integer             j;          // FC1 输入列指针 0..IN1_N-1
    integer             fc2_idx;    // FC2 累加指针 0..CHAN-1
    logic signed [23:0] fc2_acc;

    // ---------------- main FSM ----------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_IDLE;
            conv_start <= 1'b0;
            clr_all    <= 1'b0;
            ready_all  <= 1'b0;
            j          <= 0;
            fc2_idx    <= 0;
            fc2_acc    <= '0;
            done_reg   <= 1'b0;
            result_reg <= '0;
        end else begin
            conv_start <= 1'b0;
            clr_all    <= 1'b0;
            ready_all  <= 1'b0;

            unique case (state)

                S_IDLE: begin
           
                    if (ctrl_start) begin
                        conv_start <= 1'b1;
                        state      <= S_CONV_WAIT;
                    end
                end

                S_CONV_WAIT: begin
                    if (conv_done) begin
                        state <= S_CONV_DONE;
                        conv_start <= 1'b0;
                    end
                end

                S_CONV_DONE: begin
		    
                    state <= S_FCN_WAIT;
                end

                S_FCN_WAIT: begin
		    fcn_start<= 1'b1;
	    	    in_vec_wr<= 1'b1;
		    fc1_w_wr_all<= 1'b1;
		    fc2_w_wr_all<= 1'b1;
                    if (fcn_done) begin
                        result_reg <= fcn_logit;
                        done_reg   <= 1'b1;
                        fcn_start  <= 1'b0;
			in_vec_wr<= 1'b0;
		    	fc1_w_wr_all<= 1'b0;
		    	fc2_w_wr_all<= 1'b0;
                        state      <= S_DONE;
                    end
                end
                    

                S_DONE: begin
                    
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    //读路径
    reg [2:0]  sel_q;
    reg [11:0] idx_q;
    reg        re_q;

    always @(*) begin
        if (rst) begin
            sel_q  <= '0;
            idx_q  <= '0;
            re_q   <= 1'b0;
            douta  <= 32'd0;
        end else begin
            re_q  <= (ena && ~wea);
            sel_q <= sel;
            idx_q <= idx;

            if (re_q) begin
                unique case (sel_q)
                    3'b111: begin
                        case (idx_q)
                            12'd0: douta <= {31'd0, done_reg};
                            12'd4: douta <= {{8{result_reg[23]}}, result_reg};
                            default: douta <= 32'd0;
                        endcase
                    end
                    default: douta <= 32'd0;
                endcase
            end
        end
    end


endmodule
