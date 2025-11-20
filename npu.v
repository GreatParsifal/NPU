// fcn as a bus-mapped accelerator (same bus ports as npu)
// addr[14:12] sel:
//   000: in_vec[0..IN1_N-1]         (132)
//   011: fc1_w linear[0..OUT1_M*IN1_N-1] -> [neuron][k] (1320)  <-- now flat
//   100: fc2_w[0..OUT1_M-1]         (10)
//   101: control/status:
//        write idx=1 -> start
//        read  idx=0 -> {31'b0, done}
//        read  idx=1 -> {{8{result[23]}}, result}
`timescale 1ns/1ps
//`include "pe_unit_fcn.v"

module npu #(
    parameter int IN1_N  = 132,
    parameter int OUT1_M = 10
)(
    input  logic        clk,
    input  logic        rst_ni,
    // bus-style ports (compatible with npu)
    input  logic        ena,
    input  logic        wea,
    input  logic [15:0] addra,   // use [14:0] as {sel,idx}, ignore addra[15]
    input  logic [31:0] dina,
    output logic [31:0] douta
);
    // ---------------- storage ----------------
    reg  signed [7:0] in_vec  [0:IN1_N-1];
    // fc1 weights stored flat: index = neuron*IN1_N + k
    localparam int FC1_TOTAL = OUT1_M * IN1_N;
    reg  signed [7:0] fc1_w_flat [0:FC1_TOTAL-1];
    reg  signed [7:0] fc2_w   [0:OUT1_M-1];

    // ---------------- PE array ----------------
    wire signed [23:0] pe_out [0:OUT1_M-1];
    reg                clr_all, ready_all;
    reg  signed [7:0]  current_x;
    reg  signed [7:0]  w_bus [0:OUT1_M-1];

    genvar gv;
    generate
        for (gv = 0; gv < OUT1_M; gv++) begin : GEN_PE
            pe_unit_fcn u_pe (
                .clk     (clk),
                .rst_n   (rst_ni),
                .clr     (clr_all),
                .ready   (ready_all),
                .in_data1(w_bus[gv]),
                .in_data2(current_x),
                .outdata (pe_out[gv])
            );
        end
    endgenerate

    // ---------------- FSM ----------------
    typedef enum logic [2:0] {
        S_IDLE, S_CLR, S_LOAD, S_ACC, S_FC1_DONE, S_FC2_ACC, S_DONE
    } state_e;

    state_e state;
    integer i;
    integer j;                // 0..IN1_N-1
    reg  [3:0]  fc2_idx;      // 0..OUT1_M-1
    reg  signed [23:0] fc1_out_relu [0:OUT1_M-1];
    reg  signed [23:0] fc2_acc;

    // ctrl/status
    reg  ctrl_start;
    reg  done_reg;
    reg  signed [23:0] result_reg;

    wire rst = ~rst_ni;

    // ---------------- write path (ena & wea) ----------------
    wire [2:0]  sel = addra[14:12];
    wire [11:0] idx = addra[11:0];

    always_ff @(posedge clk or posedge rst) begin
       if (ena && wea) begin
            unique case (sel)
                3'b000: begin
                    // 一次写入4个8位数据到输入向量
                    if (idx < IN1_N/4) begin
                        in_vec[idx*4 + 0] <= dina[7:0];
                        in_vec[idx*4 + 1] <= dina[15:8];
                        in_vec[idx*4 + 2] <= dina[23:16];
                        in_vec[idx*4 + 3] <= dina[31:24];
                    end
                end
                3'b011: begin // fc1_w linear -> flat array
                    // 一次写入4个权重到 fc1_w_flat（线性索引）
                    // 允许尾部不足 4 个时也写入（用边界检查）
                    
                    if (idx*4 < FC1_TOTAL) begin
                        if (idx*4 + 0 < FC1_TOTAL) fc1_w_flat[idx*4 + 0] <= dina[7:0];
                        if (idx*4 + 1 < FC1_TOTAL) fc1_w_flat[idx*4 + 1] <= dina[15:8];
                        if (idx*4 + 2 < FC1_TOTAL) fc1_w_flat[idx*4 + 2] <= dina[23:16];
                        if (idx*4 + 3 < FC1_TOTAL) fc1_w_flat[idx*4 + 3] <= dina[31:24];
                    end
                end
                3'b100: begin
                    // FC2权重 - 一次写入4个
                    // (保持原样，但用边界检查以避免越界) 
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
	if(state == S_CLR) begin
		ctrl_start <= 1'b0;
	end
    end

    // ---------------- read path (SRAM-like: next cycle) ----------------
    reg [2:0]  sel_q; 
    reg [11:0] idx_q;
    reg        re_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sel_q <= '0; idx_q <= '0; re_q <= 1'b0;
            douta <= 32'd0;
            done_reg   <= 1'b0;
            result_reg <= '0;
        end else begin
            // pipeline addr when read
            re_q  <= (ena && ~wea);
            sel_q <= sel;
            idx_q <= idx;

            // update result when finishing
            if (state == S_DONE) begin
                done_reg   <= 1'b1;
                result_reg <= fc2_acc;
            end else if (state == S_IDLE) begin
                done_reg <= 1'b0; // auto-clear; 或改为等待软件读清
            end

            // return data
            if (re_q) begin
                unique case (sel_q)
                    3'b000: begin
                        // 一次读取4个输入向量数据
                        if (idx_q < IN1_N/4) begin
                            douta <= {in_vec[idx_q*4 + 3], 
                                     in_vec[idx_q*4 + 2], 
                                     in_vec[idx_q*4 + 1], 
                                     in_vec[idx_q*4 + 0]};
                        end else begin
                            douta <= 32'd0;
                        end
                    end
                    3'b011: begin
                        // 一次读取4个FC1权重（从 flat 数组读）
                       
                        logic [31:0] tmp;
                        // 每个位置都要做越界检查
                        tmp[7:0]   = (idx*4 + 0 < FC1_TOTAL) ? fc1_w_flat[idx*4 + 0] : 8'd0;
                        tmp[15:8]  = (idx*4 + 1 < FC1_TOTAL) ? fc1_w_flat[idx*4 + 1] : 8'd0;
                        tmp[23:16] = (idx*4 + 2 < FC1_TOTAL) ? fc1_w_flat[idx*4 + 2] : 8'd0;
                        tmp[31:24] = (idx*4 + 3 < FC1_TOTAL) ? fc1_w_flat[idx*4 + 3] : 8'd0;
                        douta <= tmp;
                    end
                    3'b100: begin
                        // 一次读取4个FC2权重
                        
                        logic [31:0] tmp2;
                        tmp2[7:0]   = (idx*4 + 0 < OUT1_M) ? fc2_w[idx*4 + 0] : 8'd0;
                        tmp2[15:8]  = (idx*4 + 1 < OUT1_M) ? fc2_w[idx*4 + 1] : 8'd0;
                        tmp2[23:16] = (idx*4 + 2 < OUT1_M) ? fc2_w[idx*4 + 2] : 8'd0;
                        tmp2[31:24] = (idx*4 + 3 < OUT1_M) ? fc2_w[idx*4 + 3] : 8'd0;
                        douta <= tmp2;
                    end
                    3'b101: begin
                        case (idx_q)
                            12'd0: douta <= {31'd0, done_reg};
                            12'd1: douta <= {{8{result_reg[23]}}, result_reg};
                            default: douta <= 32'd0;
                        endcase
                    end
                    default: douta <= 32'd0;
                endcase
            end
        end
    end

    // ---------------- main FSM ----------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            clr_all <= 1'b0;
            ready_all <= 1'b0;
            current_x <= 8'sd0;
            for (i = 0; i < OUT1_M; i++) begin
                w_bus[i] <= 8'sd0;
                fc1_out_relu[i] <= 24'sd0;
            end
            j <= 0;
            fc2_idx <= '0;
            fc2_acc <= '0;
        end else begin
            // defaults
            clr_all   <= 1'b0;
            ready_all <= 1'b0;

            unique case (state)
                S_IDLE: begin
                    j <= 0;
                    if (ctrl_start) begin
                        state      <= S_CLR;
                    end
                end
                S_CLR: begin
                    clr_all <= 1'b1;
                    j <= 0;
                    state <= S_LOAD;
                end
                // LOAD: latch one column (x_j and w[:,j]) -- now read from flat array
                S_LOAD: begin
                    if (j < IN1_N) begin
                        current_x <= in_vec[j];
                        // w_bus[i] <= fc1_w[i][j];  --> replaced by flat index
                        for (i = 0; i < OUT1_M; i++) begin
                            int flat_idx = i * IN1_N + j;
                            w_bus[i] <= (flat_idx < FC1_TOTAL) ? fc1_w_flat[flat_idx] : 8'sd0;
                        end
                        state <= S_ACC;
                    end else begin
                        state <= S_FC1_DONE;
                    end
                end
                // ACC: assert ready one cycle to accumulate PE
                S_ACC: begin
                    ready_all <= 1'b1;
                    j <= j + 1;
                    state <= S_LOAD;
                end
                S_FC1_DONE: begin
                    for (i = 0; i < OUT1_M; i++) begin
                        fc1_out_relu[i] <= (pe_out[i] < 0) ? 24'sd0 : pe_out[i];
                    end
                    fc2_acc <= 24'sd0;
                    fc2_idx <= '0;
                    state <= S_FC2_ACC;
                end
                S_FC2_ACC: begin
                    if (fc2_idx < OUT1_M) begin
                        // use low 8-bit after ReLU
                        logic signed [7:0] x8;
                        x8 = fc1_out_relu[fc2_idx][7:0];
                        fc2_acc <= fc2_acc + $signed(fc2_w[fc2_idx]) * $signed(x8);
                        fc2_idx <= fc2_idx + 1;
                    end else begin
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    // hold one cycle for read; return to IDLE automatically
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
