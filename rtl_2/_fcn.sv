module fcn#(
    parameter int IN1_N   = 132,
    parameter int OUT1_M  = 10,
    parameter int NUM_PE  = 4
)(
    input logic clk,
    input logic rst_n,
    input logic [7:0] in_vec[0:IN1_N-1],
    input logic signed [7:0] fc1_w [0:NUM_PE-1],
    input logic fc1_next,
    output logic fc1_valid,
    input logic signed [7:0] fc2_w [0:OUT1_M-1],
    input logic start,
    output logic done,
    output logic signed [23:0] fc2_logit
);
    logic signed [23:0] pe_out [0:NUM_PE-1];
    logic clr_all;
    logic ready_all;
    logic signed [7:0] current_x_bus [0:NUM_PE-1];
    logic signed [7:0] w_bus [0:NUM_PE-1];

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

    logic signed [23:0] fc1_out_relu [0:OUT1_M-1];

    typedef enum logic [2:0] {
        S_IDLE,
        S_PRE_CLEAR,     
        S_STREAM_W,      
        S_GROUP_DONE,    
        S_WAIT_NEXT,     
        S_FC2_ACC,
        S_DONE
    } state_e;
    state_e state;

    int input_idx;
    int neuron_base;
    int valid_pe_cnt;
    int fc2_idx;
    logic signed [23:0] fc2_acc;

    always_comb begin
        for(int k = 0; k < NUM_PE; k++) begin
            current_x_bus[k] = 8'sd0;
            w_bus[k] = 8'sd0;
        end
        if(state == S_STREAM_W) begin
            for(int k = 0; k < NUM_PE; k++) begin
                current_x_bus[k] = in_vec[input_idx];
                if(k < valid_pe_cnt) begin
                    w_bus[k] = fc1_w[k];
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= S_IDLE;
            input_idx <= 0;
            neuron_base <= 0;
            valid_pe_cnt <= 0;
            fc1_valid <= 1'b0;
            fc2_idx <= 0;
            fc2_acc <= 24'sd0;
            fc2_logit <= 24'sd0;
            clr_all <= 1'b0;
            ready_all <= 1'b0;
            for(int i = 0; i < OUT1_M; i++) begin
                fc1_out_relu[i] <= 24'sd0;
            end
        end else begin
            clr_all <= 1'b0;
            ready_all <= 1'b0;
            fc1_valid <= 1'b0;

            case(state)
                S_IDLE: begin
                    done <= 1'b0;
                    if(start) begin
                        neuron_base <= 0;
                        valid_pe_cnt <= (OUT1_M >= NUM_PE) ? NUM_PE : OUT1_M;
                        state <= S_PRE_CLEAR;
                    end
                end
                S_PRE_CLEAR: begin
                    clr_all <= 1'b1;
                    input_idx <= 0;
                    state <= S_STREAM_W;
                end
                S_STREAM_W: begin
                    ready_all <= 1'b1;
                    if (input_idx < IN1_N - 1) begin
                        input_idx <= input_idx + 1;
                    end else begin
                        input_idx <= 0;
                        state <= S_GROUP_DONE;
                    end
                end
                S_GROUP_DONE: begin
                    for (int k = 0; k < NUM_PE; k++) begin
                        if (neuron_base + k < OUT1_M) begin
                            fc1_out_relu[neuron_base + k] <= (pe_out[k] < 0) ? 24'sd0 : pe_out[k];
                        end
                    end
                    fc1_valid <= 1'b1;
                    state     <= S_WAIT_NEXT;
                end

                S_WAIT_NEXT: begin
                    if (fc1_next) begin
                        if (neuron_base + valid_pe_cnt < OUT1_M) begin
                            neuron_base  <= neuron_base + valid_pe_cnt;
                            if (OUT1_M - (neuron_base + valid_pe_cnt) >= NUM_PE)
                                valid_pe_cnt <= NUM_PE;
                            else
                                valid_pe_cnt <= OUT1_M - (neuron_base + valid_pe_cnt);
                            state <= S_PRE_CLEAR;
                        end else begin
                            fc2_idx   <= 0;
                            fc2_acc   <= 24'sd0;
                            state     <= S_FC2_ACC;
                        end
                    end
                end

                S_FC2_ACC: begin
                    logic signed [47:0] sum; // width enough: 24-bit * 8-bit -> ~32 bits product, add up to 10 => 48 safe
                    sum = 48'sd0;
                    for (int k = 0; k < OUT1_M; k = k + 1) begin
                        sum = sum + $signed(fc1_out_relu[k]) * $signed(fc2_w[k]);
                    end
                    fc2_acc <= sum;         // update register once
                    fc2_logit <= sum[23:0]; // or wait next cycle if you prefer
                    state <= S_DONE;
                end

                S_DONE: begin
                    done <= 1'b1;
                    if (!start) begin
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

    


endmodule