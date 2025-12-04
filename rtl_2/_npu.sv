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

    localparam int IMG_SIZE = IN1_H*IN1_W;
    localparam int WC_SIZE  = K_H*K_W;
    localparam int FV_LEN   = OUT2_H*OUT2_W;

    //conv layer
    logic [7:0] img_in_flat  [0:IMG_SIZE-1];
    logic signed [7:0] w_conv_flat [0:WC_SIZE-1];
    logic signed [7:0] w_conv [K_H][K_W];
    
    logic [7:0] conv_out     [0:OUT2_H-1][0:OUT2_W-1];
    logic [7:0] in_vec_array [0:IN1_N-1];

    //fc layer
    logic signed [7:0] fc2_w        [0:OUT1_M-1];
    logic signed [7:0] curr_w_stream [0:NUM_PE-1];

    genvar gi, gj, gk;
    // reshape w_conv_flat to w_conv
    generate
        for (gi = 0; gi < K_H; gi++) begin : GEN_CONV
            for (gj = 0; gj < K_W; gj++) begin : GEN_CONV_W
                assign w_conv[gi][gj] = w_conv_flat[gi*K_W + gj];
            end
        end
    endgenerate

    // flatten conv_out to in_vec_array
    generate
        for (gi = 0; gi < OUT2_H; gi++) begin : GEN_INVEC
            for (gj = 0; gj < OUT2_W; gj++) begin : GEN_INVEC_W
                assign in_vec_array[gi*OUT2_W + gj] = conv_out[gi][gj];
            end
        end
    endgenerate

    //conv module
    logic clear_conv_addr;
    logic host_trigger;
    logic host_save_done;
    logic layer;
    logic pixel_valid;
    logic signed [23:0] out_pixel_full;
    logic [7:0] conv1_out_pixel;
    logic [7:0] pixel_addr;
    
    conv  u_conv (
        .clk(clk),
        .rst_n(rst_ni),
        .clear(clear_conv_addr),
        .in_img(img_in_flat),
        .w_conv(w_conv),
        .trigger(host_trigger),
        .layer(layer),
        .out_pixel(out_pixel_full),
        .addr(pixel_addr),
        .valid(pixel_valid),
        .save_done(save_done_sim)
    );

    assign conv1_out_pixel = out_pixel_full[7:0];

    // data package module
    logic save_done_sim;
    logic pack_valid;
    logic [31:0] conv1_out_pack;
    pack u_pack (
        .clk(clk),
        .rst_n(rst_ni),
        .pixel_valid(pixel_valid),
        .save_done(host_save_done),
        .in_data(out_pixel_full[7:0]),
        .save_done_sim(save_done_sim),
        .pack_valid(pack_valid),
        .pack_out_data(conv1_out_pack)
    );

    // conv_out buffer
    logic clear_sum;
    logic signed [23:0] conv2_out_full [0:OUT2_H-1][0:OUT2_W-1];

    partial_sum  u_partial_sum (
        .clk(clk),
        .ce(layer),
        .rst_n(rst_ni),
        .clear(clear_sum),
        .addr(pixel_addr),
        .in_valid(host_save_done),
        .in_data(out_pixel_full),
        .out_data(conv2_out_full)
    );

    for (gi = 0; gi < OUT2_H; gi++) begin : GEN_CONV_OUT_H
        for (gj = 0; gj < OUT2_W; gj++) begin : GEN_CONV_OUT_W
            assign conv_out[gi][gj] = conv2_out_full[gi][gj][23] ? 8'd0 : conv2_out_full[gi][gj][7:0]; // Relu
        end
    end

    //fc module
    logic fcn_start;
    logic signed [7:0] w_stream [0:NUM_PE-1];
    logic fcn_done;
    logic signed [23:0] fcn_logit;
    logic fcn_fc1_valid;
    logic fcn_fc1_next;

    fcn  u_fcn (
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

    logic host_wea;
    assign host_wea = rst ? 1'b0 : (ena & wea);
    logic host_rea;
    assign host_rea = rst ? 1'b0 : (ena & ~wea);
    logic done_reg;
    logic signed [23:0] result_reg;
    logic fc1_group_valid_reg;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i=0;i<IMG_SIZE;i++) img_in_flat[i] <= 8'd0;
            for (int i=0;i<WC_SIZE;i++) w_conv_flat[i] <= 8'd0;
            for (int i=0;i<OUT1_M;i++) fc2_w[i] <= 8'sd0;
            for (int p=0;p<NUM_PE;p++) curr_w_stream[p] <= 8'sd0;
        end else if (host_wea) begin
            unique case (sel)
                3'b001: begin
                    if (idx*4+0 < IMG_SIZE) img_in_flat[idx*4+0] <= dina[7:0];
                    if (idx*4+1 < IMG_SIZE) img_in_flat[idx*4+1] <= dina[15:8];
                    if (idx*4+2 < IMG_SIZE) img_in_flat[idx*4+2] <= dina[23:16];
                    if (idx*4+3 < IMG_SIZE) img_in_flat[idx*4+3] <= dina[31:24];
                end
                3'b010: begin
                    if (idx*4+0 < WC_SIZE) w_conv_flat[idx*4+0] <= dina[7:0];
                    if (idx*4+1 < WC_SIZE) w_conv_flat[idx*4+1] <= dina[15:8];
                    if (idx*4+2 < WC_SIZE) w_conv_flat[idx*4+2] <= dina[23:16];
                    if (idx*4+3 < WC_SIZE) w_conv_flat[idx*4+3] <= dina[31:24];
                end
                3'b011: begin
                    curr_w_stream[0] <= dina[7:0];
                    curr_w_stream[1] <= dina[15:8];
                    curr_w_stream[2] <= dina[23:16];
                    curr_w_stream[3] <= dina[31:24];
                end
                3'b100: begin
                    if (idx*4+0 < OUT1_M) fc2_w[idx*4+0] <= dina[7:0];
                    if (idx*4+1 < OUT1_M) fc2_w[idx*4+1] <= dina[15:8];
                    if (idx*4+2 < OUT1_M) fc2_w[idx*4+2] <= dina[23:16];
                    if (idx*4+3 < OUT1_M) fc2_w[idx*4+3] <= dina[31:24];
                end
                3'b101: begin
                    // host_layer should keep 0 as conv1 calculating, 1 as conv2 calculating
                end
                default: ;
            endcase
        end
        else if (host_rea) begin
            unique case (sel)
		        3'b111:
                case(idx)
                    12'd0: douta <= {31'd0, done_reg};
                    12'd4: douta <= {{8{result_reg[23]}}, result_reg};
                    12'd8: douta <= {31'd0, pack_valid};
                    12'd12: douta <= conv1_out_pack;
                    12'd16: douta <= {31'b0, fc1_group_valid_reg};
                    12'd20: douta <= {31'b0, fcn_done};
                    default: douta <= 32'd0;
                endcase
                default: douta <= 32'd0;
            endcase
        end
    end

    //control FSM
    typedef enum logic [2:0] {
        S_IDLE,
        S_CONV1,
        S_CONV2_WAIT,
        S_CONV2,
        S_READY_FCN,
        S_DONE
    }state_e;
    state_e state;


    
    

    logic host_start_single_req;
    logic host_fc1_next_req;
    
    // FSM for trigger signals
    logic host_next_layer;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            host_trigger <= 1'b0;
            host_save_done <= 1'b0;
            host_next_layer <= 1'b0;
            host_start_single_req <= 1'b0;
            host_fc1_next_req <= 1'b0;
        end else if (host_wea && sel==3'b101) begin
            host_trigger <= dina[0];
            host_save_done <= dina[2];
            host_next_layer <= dina[3];
            host_start_single_req <= dina[4];
            host_fc1_next_req <= dina[1];
        end else begin
            host_trigger <= 1'b0;
            host_save_done <= 1'b0;
            host_next_layer <= 1'b0;
            host_start_single_req <= 1'b0;
            host_fc1_next_req <= 1'b0;
        end
    end

    // main
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
                    clear_conv_addr <= 1'b0;
                    if (host_trigger) begin
                        state <= S_CONV1;
                        layer <= 1'b0; // conv1
                    end else if (host_next_layer) begin // change to conv2
                        state <= S_CONV2_WAIT;
                        layer <= 1'b1; // conv2
                        clear_sum <= 1'b0;
                        clear_conv_addr <= 1'b1;
                    end 
                end
                S_CONV1: begin
                    if (pixel_addr == 182) begin
                        state <= S_IDLE;
                        clear_conv_addr <= 1'b1;
                    end
                end
                S_CONV2_WAIT: begin
                    clear_conv_addr <= 1'b0;
                    if (host_next_layer) begin // change to conv2
                        state <= S_READY_FCN;
                        layer <= 1'b0; // disable partial sum
                    end else if (host_trigger) begin
                        state <= S_CONV2;
                    end
                end
                S_CONV2: begin
                    if (pixel_addr == 132) begin
                        state <= S_CONV2_WAIT;
                        clear_conv_addr <= 1'b1;
                    end
                end
                S_READY_FCN: begin
                    if (host_start_single_req) begin
                        for (int p=0; p<NUM_PE; p++) begin
                            w_stream[p] <= curr_w_stream[p];
                        end
                        fcn_start <= 1'b1;
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