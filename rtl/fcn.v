module fcn #(
    parameter int IN1_N   = 132,
    parameter int OUT1_M  = 10,
    parameter int NUM_PE  = 4
)(
    input  logic clk,
    input  logic rst_n,

    input  logic [7:0]  in_vec_array [0:IN1_N-1],

    input  logic signed [7:0] w_stream [0:NUM_PE-1],
    input  logic              w_valid,

    input  logic signed [7:0] fc2_w_array  [0:OUT1_M-1],

    input  logic start,
    output logic done,
    output logic signed [23:0] fc2_logit,

    output logic fc1_valid,
    input  logic fc1_next
);

    logic signed [23:0] pe_out [0:NUM_PE-1];
    reg clr_all;
    reg ready_all;
    logic signed [7:0] current_x_bus [0:NUM_PE-1];
    reg signed [7:0] w_bus [0:NUM_PE-1];

    genvar gv;
    generate
        for (gv = 0; gv < NUM_PE; gv = gv + 1) begin : PEs
            pe_unit_fcn pe_inst (
                .clk(clk),
                .rst_n(rst_n),
                .clr(clr_all),
                .ready(ready_all),
                .in_data1(w_bus[gv]),
                .in_data2(current_x_bus[gv]),
                .outdata(pe_out[gv])
            );
        end
    endgenerate

    reg signed [23:0] fc1_out_relu [0:OUT1_M-1];

    localparam S_IDLE      = 0,
               S_PRE_CLEAR = 1,
               S_STREAM_W  = 2,
               S_GROUP_DONE= 3,
               S_WAIT_NEXT = 4,
               S_FC2_ACC   = 5,
               S_DONE      = 6;

    reg [2:0] state;

    integer input_idx;      // steps through inputs for current neuron, step = NUM_PE
    integer neuron_idx;     // current neuron being processed (0..OUT1_M-1)
    integer p;

    reg [4:0] fc2_idx;
    reg signed [31:0] fc2_acc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            input_idx <= 0;
            neuron_idx <= 0;
            done <= 1'b0;
            clr_all <= 1'b0;
            ready_all <= 1'b0;
            for (p = 0; p < NUM_PE; p = p + 1) begin
                current_x_bus[p] <= 8'sd0;
                w_bus[p] <= 8'sd0;
            end
            for (p = 0; p < OUT1_M; p = p + 1) fc1_out_relu[p] <= 24'sd0;
            fc2_acc <= 32'sd0;
            fc2_idx <= 0;
            fc2_logit <= 24'sd0;
            fc1_valid <= 1'b0;
        end else begin
            clr_all <= 1'b0;
            ready_all <= 1'b0;
            done <= 1'b0;
            fc1_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    input_idx <= 0;
                    neuron_idx <= 0;
                    if (start) state <= S_PRE_CLEAR;
                end

                S_PRE_CLEAR: begin
                    clr_all <= 1'b1;
                    input_idx <= 0;
                    for (p = 0; p < NUM_PE; p = p + 1) begin
                        w_bus[p] <= 8'sd0;
                        current_x_bus[p] <= 8'sd0;
                    end
                    state <= S_STREAM_W;
                end

                S_STREAM_W: begin
                    if (w_valid) begin
                        // load current inputs (NUM_PE values) for this cycle, pad with 0 if beyond IN1_N
                        for (p = 0; p < NUM_PE; p = p + 1) begin
                            if ((input_idx + p) < IN1_N) begin
                                current_x_bus[p] <= $signed({1'b0, in_vec_array[input_idx + p]});
                            end else begin
                                current_x_bus[p] <= 8'sd0;
                            end
                        end

                        // take weights for the same neuron (CPU must provide w_stream corresponding to
                        // weights for neuron 'neuron_idx' at input indices input_idx + p)
                        for (p = 0; p < NUM_PE; p = p + 1) begin
                            if ( (input_idx + p) < IN1_N )
                                w_bus[p] <= w_stream[p];
                            else
                                w_bus[p] <= 8'sd0;
                        end

                        ready_all <= 1'b1;

                        // advance input index by NUM_PE
                        if (input_idx + NUM_PE < IN1_N) input_idx <= input_idx + NUM_PE;
                        else begin
                            input_idx <= 0;
                            state <= S_GROUP_DONE;
                        end
                    end
                end

                S_GROUP_DONE: begin
                    // sum partial accumulators from PEs to get neuron total
                    // pe_out[p] holds each PE's accumulated partial sum for this neuron
                    signed [31:0] sum;
                    sum = 32'sd0;
                    for (p = 0; p < NUM_PE; p = p + 1) begin
                        sum = sum + $signed(pe_out[p]);
                    end

                    if (sum < 0) fc1_out_relu[neuron_idx] <= 24'sd0;
                    else fc1_out_relu[neuron_idx] <= sum[23:0];

                    fc1_valid <= 1'b1;
                    state <= S_WAIT_NEXT;
                end

                S_WAIT_NEXT: begin
                    if (fc1_next) begin
                        integer next_neuron;
                        next_neuron = neuron_idx + 1;
                        neuron_idx <= next_neuron;
                        if (next_neuron >= OUT1_M) begin
                            fc2_acc <= 32'sd0;
                            fc2_idx <= 0;
                            state <= S_FC2_ACC;
                        end else begin
                            state <= S_PRE_CLEAR;
                        end
                    end
                end

                S_FC2_ACC: begin
                    if (fc2_idx < OUT1_M) begin
                        logic [7:0] in_x8u;
                        logic signed [8:0] in_x8_s;
                        in_x8u = fc1_out_relu[fc2_idx][7:0];
                        in_x8_s = $signed({1'b0, in_x8u});
                        fc2_acc <= fc2_acc + ($signed(fc2_w_array[fc2_idx]) * in_x8_s);
                        fc2_idx <= fc2_idx + 1;
                    end else begin
                        fc2_logit <= fc2_acc[23:0];
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
