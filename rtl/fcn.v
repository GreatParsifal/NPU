// FC1: IN=132, OUT=10
// FC2: IN=10, OUT=1
//already tested by Verilator
`include "pe_unit_fcn.v"
module fcn (
    input  wire clk,
    input  wire rst_n,
    // external write interfaces
    input  wire        in_wr,        // 写入输入向量
    input  wire [7:0]  in_addr,      // 0..131
    input  wire signed [7:0] in_data, // 输入数据

    input  wire        fc1_w_wr,     // 写入 fc1 权重
    input  wire [15:0] fc1_w_addr,   // 地址: neuron_idx * 132 + weight_idx
    input  wire signed [7:0] fc1_w_data,

    input  wire        fc2_w_wr,     // 写入 fc2 权重 (0..9)
    input  wire [3:0]  fc2_w_addr,
    input  wire signed [7:0] fc2_w_data,

    input  wire        start,
    output reg         done,
    output reg signed [23:0] fc2_logit
);

    // parameters
    localparam IN1_N = 132;
    localparam OUT1_M = 10;

    // internal memories
    reg signed [7:0] in_vec [0:IN1_N-1];
    reg signed [7:0] fc1_w [0:OUT1_M-1][0:IN1_N-1];
    reg signed [7:0] fc2_w [0:OUT1_M-1];

    // instantiate 10 PEs
    wire signed [23:0] pe_out [0:OUT1_M-1];
    reg clr_all;
    reg ready_all;
    reg signed [7:0] current_x;
    reg signed [7:0] w_bus [0:OUT1_M-1];

    genvar gv;
    generate
        for (gv = 0; gv < OUT1_M; gv = gv + 1) begin : PEs
            pe_unit_fcn pe_inst (
                .clk(clk),
                .rst_n(rst_n),
                .clr(clr_all),
                .ready(ready_all),
                .in_data1(w_bus[gv]),
                .in_data2(current_x),
                .outdata(pe_out[gv])
            );
        end
    endgenerate

    // FC1 outputs (internal)
    reg signed [23:0] fc1_out_relu [0:OUT1_M-1];

    // FSM
    localparam S_IDLE      = 0,
               S_CLR       = 1,
               S_STREAM    = 2,
               S_FC1_DONE  = 3,
               S_FC2_ACC   = 4,
               S_DONE      = 5;

    reg [2:0] state;
    integer j; // index over input elements (used in sequential logic)
    integer i;

    // Additional integer locals for address decode to avoid reusing 'j'
    integer neuron_idx;
    integer weight_idx;

    reg [3:0] fc2_idx;
    reg signed [23:0] fc2_acc;

    // external write handling
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // initialize memories to zero (use separate loop index kk)
            integer kk, ll;
            for (kk = 0; kk < IN1_N; kk = kk + 1) in_vec[kk] <= 8'sd0;
            for (kk = 0; kk < OUT1_M; kk = kk + 1) begin
                fc2_w[kk] <= 8'sd0;
                for (ll = 0; ll < IN1_N; ll = ll + 1) fc1_w[kk][ll] <= 8'sd0;
            end
        end else begin
            if (in_wr) begin
                if (in_addr < IN1_N) in_vec[in_addr] <= in_data;
            end
            if (fc1_w_wr) begin
                // decode addr to neuron and weight idx
                neuron_idx = fc1_w_addr / IN1_N;
                weight_idx = fc1_w_addr % IN1_N;
                if (neuron_idx >= 0 && neuron_idx < OUT1_M && weight_idx >=0 && weight_idx < IN1_N) begin
                    fc1_w[neuron_idx][weight_idx] <= fc1_w_data;
                end
            end
            if (fc2_w_wr) begin
                if (fc2_w_addr < OUT1_M) fc2_w[fc2_w_addr] <= fc2_w_data;
            end
        end
    end

    // main FSM sequential
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            j <= 0;
            done <= 1'b0;
            clr_all <= 1'b0;
            ready_all <= 1'b0;
            current_x <= 8'sd0;
            for (i = 0; i < OUT1_M; i = i + 1) begin
                w_bus[i] <= 8'sd0;
                fc1_out_relu[i] <= 24'sd0;
            end
            fc2_acc <= 24'sd0;
            fc2_idx <= 0;
            fc2_logit <= 24'sd0;
        end else begin
            // default signals
            clr_all <= 1'b0;
            ready_all <= 1'b0;
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    j <= 0;
                    if (start) state <= S_CLR;
                end

                S_CLR: begin
                    // clear all PE accumulators (one-cycle pulse)
                    clr_all <= 1'b1;
                    j <= 0;
                    state <= S_STREAM;
                end

                S_STREAM: begin
                    if (j < IN1_N) begin
                        current_x <= in_vec[j];
                        // drive weight bus
                        for (i = 0; i < OUT1_M; i = i + 1) begin
                            w_bus[i] <= fc1_w[i][j];
                        end
                        ready_all <= 1'b1; // perform MAC on this element
                        j <= j + 1;
                    end else begin
                        // finished streaming
                        state <= S_FC1_DONE;
                    end
                end

                S_FC1_DONE: begin
                    // read PE outputs and apply ReLU
                    for (i = 0; i < OUT1_M; i = i + 1) begin
                        if (pe_out[i] < 0) fc1_out_relu[i] <= 24'sd0;
                        else fc1_out_relu[i] <= pe_out[i];
                    end
                    // prepare FC2 accumulation
                    fc2_acc <= 24'sd0;
                    fc2_idx <= 0;
                    state <= S_FC2_ACC;
                end

                S_FC2_ACC: begin
                    if (fc2_idx < OUT1_M) begin
                        // simple truncation to 8-bit for demo (production: use consistent fixed-point)
                        reg signed [7:0] in_x8;
                        in_x8 = fc1_out_relu[fc2_idx][7:0];
                        fc2_acc <= fc2_acc + $signed(fc2_w[fc2_idx]) * $signed(in_x8);
                        fc2_idx <= fc2_idx + 1;
                    end else begin
                        fc2_logit <= fc2_acc;
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
