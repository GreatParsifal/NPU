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

    ocalparam int IMG_SIZE = IN1_H*IN1_W;
    localparam int WC_SIZE  = K_H*K_W*CHAN;
    localparam int FV_LEN   = OUT2_H*OUT2_W;

    //conv layer
    logic [7:0] img_in_flat  [0:IMG_SIZE-1];
    
    logic [7:0] conv_out     [0:OUT2_H-1][0:OUT2_W-1];
    logic [7:0] in_vec_array [0:IN1_N-1];

    //fc layer
    logic signed [7:0] fc2_w        [0:OUT1_M-1];
    logic signed [7:0] curr_w_stream [0:NUM_PE-1];

    genvar gi, gj, gk;
    generate
        for (gi = 0; gi < OUT2_H; gi++) begin : GEN_INVEC
            for (gj = 0; gj < OUT2_W; gj++) begin : GEN_INVEC_W
                assign in_vec_array[gi*OUT2_W + gj] = conv_out[gi][gj];
            end
        end
    endgenerate

    //conv module

    //fc module
    logic fcn_start;
    logic signed [7:0] w_stream [0:NUM_PE-1];
    logic fcn_done;
    logic signed [23:0] fcn_logit;
    logic fcn_fc1_valid;
    logic fcn_fc1_next;

    fcn # u_fcn (
        .clk(clk),
        .rst_n(~rst),
        .in_vec(in_vec_array),
        .fc1_w(w_stream),
        .fc1_next(fcn_fc1_next),
        .fc1_valid(fcn_fc1_valid),
        .fc2_w(fc2_w),
        .start(fcn_start),
        .done(fcn_done),
        .fc2_logit(fcn_logit)
    );

    //addr decode
    wire [2:0] sel = addra[14:12];
    wire [11:0] idx = addra[11:0];
    logic host_trigger;
    logic host_wea;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) host_wea <= 1'b0;
        else host_wea <= (ena && wea);
    end
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i=0;i<IMG_SIZE;i++) img_in_flat[i] <= 8'd0;
            for (int i=0;i<WC_SIZE;i++) w_conv1_flat[i] <= 8'd0;
            for (int i=0;i<WC_SIZE;i++) w_conv2_flat[i] <= 8'd0;
            for (int i=0;i<OUT1_M;i++) fc2_w[i] <= 8'sd0;
            for (int p=0;p<NUM_PE;p++) curr_w_stream[p] <= 8'sd0;
        end else if (host_wea) begin
            int base = idx * 4;
            unique case (sel)
                3'b110: begin
                    if (base+0 < IMG_SIZE) img_in_flat[base+0] <= dina[7:0];
                    if (base+1 < IMG_SIZE) img_in_flat[base+1] <= dina[15:8];
                    if (base+2 < IMG_SIZE) img_in_flat[base+2] <= dina[23:16];
                    if (base+3 < IMG_SIZE) img_in_flat[base+3] <= dina[31:24];
                end
                3'b001: begin
                    if (base+0 < WC_SIZE) w_conv1_flat[base+0] <= dina[7:0];
                    if (base+1 < WC_SIZE) w_conv1_flat[base+1] <= dina[15:8];
                    if (base+2 < WC_SIZE) w_conv1_flat[base+2] <= dina[23:16];
                    if (base+3 < WC_SIZE) w_conv1_flat[base+3] <= dina[31:24];
                end
                3'b010: begin
                    if (base+0 < WC_SIZE) w_conv2_flat[base+0] <= dina[7:0];
                    if (base+1 < WC_SIZE) w_conv2_flat[base+1] <= dina[15:8];
                    if (base+2 < WC_SIZE) w_conv2_flat[base+2] <= dina[23:16];
                    if (base+3 < WC_SIZE) w_conv2_flat[base+3] <= dina[31:24];
                end
                3'b011: begin
                    curr_w_stream[0] <= dina[7:0];
                    curr_w_stream[1] <= dina[15:8];
                    curr_w_stream[2] <= dina[23:16];
                    curr_w_stream[3] <= dina[31:24];
                end
                3'b100: begin
                    if (base+0 < OUT1_M) fc2_w[base+0] <= dina[7:0];
                    if (base+1 < OUT1_M) fc2_w[base+1] <= dina[15:8];
                    if (base+2 < OUT1_M) fc2_w[base+2] <= dina[23:16];
                    if (base+3 < OUT1_M) fc2_w[base+3] <= dina[31:24];
                end
                3'b101: begin
                    host_trigger <= 1'b1;
                end
                default: ;
            endcase
        end
    end

    //control FSM
    typedef enum logic [2:0] {

    }state_e;
    state_e state;

    logic fc1_group_valid_reg;
    logic done_reg;
    logic signed [23:0] result_reg;

    logic host_start_single_req;
    logic host_fc1_next_req;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            host_start_single_req <= 1'b0;
            host_fc1_next_req    <= 1'b0;
        end else begin
            if (host_wea && sel==3'b101 && idx==12'd2) host_start_single_req <= 1'b1;
            else host_start_single_req <= 1'b0;

            if (host_wea && sel==3'b101 && idx==12'd3) host_fc1_next_req <= 1'b1;
            else host_fc1_next_req <= 1'b0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            fc1_group_valid_reg <= 1'b0;
            done_reg <= 1'b0;
            result_reg <= 24'sd0;
            fcn_start <= 1'b0;
            fcn_fc1_next <= 1'b0;
            for (int p=0; p<NUM_PE; p++) w_stream[p] <= 8'sd0;
        end else begin
            fcn_start <= 1'b0;
            fcn_fc1_next <= 1'b0;
            done_reg <= 1'b0;
            unique case (state)
                S_IDLE: begin
                    if (host_trigger) begin
                        
                        state <= ;
                    end
                end

                S_READY_FCN: begin
                    if (host_start_single_req) begin
                        for (int p=0; p<NUM_PE; p++) w_stream[p] <= [p];
                    end

                    if (host_fc1_next_req) begin
                        fcn_fc1_next <= 1'b1;
                        fc1_group_valid_reg <= 1'b0;
                    end

                    if (fcn_fc1_valid) begin
                        fc1_group_valid_reg <= 1'b1;
                    end

                    if (fcn_done) begin
                        done_reg <= 1'b1;
                        result_reg <= fcn_logit;
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    state <= S_IDLE;
                end
                
                default: ;
            endcase
        end
    end




endmodule