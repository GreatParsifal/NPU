// fcn.v


module fcn #(
    parameter int IN1_N  = 132,
    parameter int OUT1_M = 10
)(
    input  clk,
    input  rst_n,

    // write ports
    input  in_vec_wr,               // write input
    input  logic [7:0]  in_vec_array [0:IN1_N-1],    // [0] .. [IN1_N-1]

    input  fc1_w_wr_all,            // write entire fc1 weight matrix in one cycle
    input  logic  signed [7:0] fc1_w_array  [0:OUT1_M-1][0:IN1_N-1], // neuron-major: [neuron][weight_idx]

    input  fc2_w_wr_all,            // write entire fc2 weight vector in one cycle
    input  logic  signed [7:0] fc2_w_array  [0:OUT1_M-1],   // fc2_w_array[0..OUT1_M-1]

    // control and outputs
    input  start,
    output logic done,
    output logic signed [23:0] fc2_logit
);

    // internal memories (same layout as before)
    reg signed [7:0] in_vec  [0:IN1_N-1];
    reg signed [7:0] fc1_w   [0:OUT1_M-1][0:IN1_N-1];
    reg signed [7:0] fc2_w   [0:OUT1_M-1];

    // PEs and helpers
    logic signed [23:0] pe_out [0:OUT1_M-1];
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

    // FSM states
    localparam S_IDLE      = 0,
               S_CLR       = 1,
               S_STREAM    = 2,
               S_FC1_DONE  = 3,
               S_FC2_ACC   = 4,
               S_DONE      = 5;

    reg [2:0] state;
    integer j;
    integer i;

    reg [3:0] fc2_idx;
    reg signed [23:0] fc2_acc;

    // handle one-cycle array writes and reset initialization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            integer kk, ll;
            for (kk = 0; kk < IN1_N; kk = kk + 1) in_vec[kk] <= 8'sd0;
            for (kk = 0; kk < OUT1_M; kk = kk + 1) begin
                fc2_w[kk] <= 8'sd0;
                for (ll = 0; ll < IN1_N; ll = ll + 1) fc1_w[kk][ll] <= 8'sd0;
            end
        end else begin
            if (in_vec_wr) begin
                integer idx;
                for (idx = 0; idx < IN1_N; idx = idx + 1) begin
                    in_vec[idx] <= in_vec_array[idx];
                end
            end

            if (fc1_w_wr_all) begin
                integer n, w;
                for (n = 0; n < OUT1_M; n = n + 1) begin
                    for (w = 0; w < IN1_N; w = w + 1) begin
                        fc1_w[n][w] <= fc1_w_array[n][w];
                    end
                end
            end

            if (fc2_w_wr_all) begin
                integer m;
                for (m = 0; m < OUT1_M; m = m + 1) begin
                    fc2_w[m] <= fc2_w_array[m];
                end
            end
        end
    end

    // --- main FSM sequential ---
    always_ff @(posedge clk or negedge rst_n) begin
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
            // defaults
            clr_all <= 1'b0;
            ready_all <= 1'b0;
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    j <= 0;
                    if (start) state <= S_CLR;
                end
                S_CLR: begin
                    clr_all <= 1'b1;
                    j <= 0;
                    state <= S_STREAM;
                end
                S_STREAM: begin
                    if (j < IN1_N) begin
                        current_x <= in_vec[j];
                        for (i = 0; i < OUT1_M; i = i + 1) begin
                            w_bus[i] <= fc1_w[i][j];
                        end
                        ready_all <= 1'b1;
                        j <= j + 1;
                    end else begin
                        state <= S_FC1_DONE;
                    end
                end
                S_FC1_DONE: begin
                    for (i = 0; i < OUT1_M; i = i + 1) begin
                        if (pe_out[i] < 0) fc1_out_relu[i] <= 24'sd0;
                        else fc1_out_relu[i] <= pe_out[i];
                    end
                    fc2_acc <= 24'sd0;
                    fc2_idx <= 0;
                    state <= S_FC2_ACC;
                end
                S_FC2_ACC: begin
                    if (fc2_idx < OUT1_M) begin
                        logic signed [7:0] in_x8;
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