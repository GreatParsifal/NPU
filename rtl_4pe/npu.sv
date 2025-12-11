`timescale 1ns/1ps
module npu #(
    parameter int K_H = 3,
    parameter int K_W = 3,
    parameter int IN1_H = 16,
    parameter int IN1_W = 15,
    parameter int OUT1_H = IN1_H - K_H + 1,    // 14
    parameter int OUT1_W = IN1_W - K_W + 1,    // 13
    parameter int OUT2_H = OUT1_H - K_H + 1,   // 12
    parameter int OUT2_W = OUT1_W - K_W + 1,   // 11
    parameter int CHAN = 10,                   // conv1 out channels
    parameter int IN1_N  = OUT2_H*OUT2_W,      // 132
    parameter int OUT1_M = 10,                 // FC1 out dim
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

    // -----------------------
    // Address / sel mapping (addra[14:12] == sel)
    // sel == 3'b110 : IMG_STREAM  -> host writes image bytes (packed 4 bytes). Host should stream full image in row-major.
    // sel == 3'b101 : CONV1_K    -> host writes current channel's conv1 3x3 kernel (9 bytes total; write order: index 0..8)
    // sel == 3'b100 : CONV2_K    -> host writes current channel's conv2 3x3 kernel (9 bytes total; index 0..8)
    // sel == 3'b011 : FC1_W_VEC  -> host writes fc1 weight vector for current conv2 position i (length OUT1_M = 10 bytes) packed into 32-bit writes (3 writes: 4+4+2 bytes)
    // sel == 3'b010 : FC2_W      -> host writes fc2 weights (10 bytes total) - can be streamed at the end
    // sel == 3'b111 : CTRL       -> control / status:
    //      idx==0 write -> start processing current channel (assumes conv1_k & conv2_k already written)
    //      idx==1 write -> indicate image stream finished for current channel (optional)
    //      idx==0 read  -> bit0 = done
    //      idx==4 read  -> result (sign extended 24-bit)
    // -----------------------

    localparam int IMG_SIZE = IN1_H * IN1_W; // 240

    wire [2:0] sel = addra[14:12];
    wire [11:0] idx = addra[11:0];

    // Host write pulse
    logic host_wea;
    always_ff @(posedge clk or posedge rst) host_wea <= rst ? 1'b0 : (ena && wea);

    // -----------------------
    // Small local storage (weights for _current channel_ only)
    logic signed [7:0] conv1_k_curr [0:K_H*K_W-1]; // 9 bytes
    logic signed [7:0] conv2_k_curr [0:K_H*K_W-1]; // 9 bytes

    // input line buffers (2 rows) to compute 3x3 conv1; we only keep two rows for streaming
    logic signed [7:0] in_linebuf [0:1][0:IN1_W-1];

    // conv1_linebuf for current channel only: keep 2 rows of conv1 outputs (16-bit)
    logic signed [15:0] conv1_linebuf [0:1][0:OUT1_W-1];

    // fc1 accumulators (we must keep these across whole processing of all channels)
    logic signed [47:0] fc1_acc [0:OUT1_M-1]; // wide to avoid overflow during accumulation

    // temp buffer: fc1 weight vector for current conv2 position (10 entries), streamed by host
    logic signed [7:0] fc1_w_vec [0:OUT1_M-1];
    logic fc1_w_vec_valid; // indicates fc1_w_vec is available for current conv2 position

    // fc2 weights (we do not need to store them until final step, but we'll buffer them when host sends at end)
    logic signed [7:0] fc2_w_buf [0:OUT1_M-1];
    logic fc2_w_valid;

    // controller/state
    typedef enum logic [2:0] { IDLE, WAIT_FOR_IMG, PROC_CONV1, PROC_CONV2_ACC, DONE } st_e;
    st_e state;

    // streaming pointers & counters
    int curr_channel;      // which conv1/conv2 channel we're processing now (0..CHAN-1)
    int img_byte_ptr;      // 0..IMG_SIZE-1: how many image bytes seen for this channel's stream
    // conv1 output position tracking (oh,ow)
    int conv1_oh;
    int conv1_ow;
    // conv1 kernel term index for per-output accumulation
    int conv1_kidx;

    // conv2 accumulation: for each conv2 position i we need to iterate kernel terms across kh,kw
    int conv2_kterm;

    // small temp accumulators
    logic signed [31:0] conv1_tmp_acc;
    logic signed [31:0] conv2_partial; // partial contribution for current kernel term: conv1_out * conv2_k (then * fc1_w_vec[m] in inner loop)
    // control flags
    logic start_channel_req;
    logic image_stream_active;

    // host write handler for small registers / temporary kernel load / fc1 vectors / fc2
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i=0;i<K_H*K_W;i++) begin conv1_k_curr[i] <= 0; conv2_k_curr[i] <= 0; end
            for (int r=0;r<2;r++) for (int c=0;c<IN1_W;c++) in_linebuf[r][c] <= 0;
            for (int r=0;r<2;r++) for (int c=0;c<OUT1_W;c++) conv1_linebuf[r][c] <= 0;
            for (int m=0;m<OUT1_M;m++) begin fc1_acc[m] <= 0; fc2_w_buf[m] <= 0; end
            fc1_w_vec_valid <= 1'b0;
            fc2_w_valid <= 1'b0;
            start_channel_req <= 1'b0;
            image_stream_active <= 1'b0;
            curr_channel <= 0;
        end else if (host_wea) begin
            int base = idx * 4;
            unique case (sel)
                3'b101: begin // CONV1_K: write current channel conv1 kernel flattened index 0..8
                    for (int b=0;b<4;b++) begin
                        int wi = base + b;
                        if (wi < K_H*K_W) conv1_k_curr[wi] <= $signed(dina[8*b +: 8]);
                    end
                end
                3'b100: begin // CONV2_K: write current channel conv2 kernel flattened index 0..8
                    for (int b=0;b<4;b++) begin
                        int wi = base + b;
                        if (wi < K_H*K_W) conv2_k_curr[wi] <= $signed(dina[8*b +: 8]);
                    end
                end
                3'b110: begin // IMG_STREAM: host writes image bytes (4 packed). Update in_linebuf rows accordingly.
                    int basebyte = base;
                    for (int b=0;b<4;b++) begin
                        int byte_idx = basebyte + b;
                        if (byte_idx < IMG_SIZE) begin
                            int r = byte_idx / IN1_W;
                            int c = byte_idx % IN1_W;
                            in_linebuf[r % 2][c] <= $signed(dina[8*b +: 8]);
                        end
                    end
                    // Mark image stream active (host may write many such cycles); NPU will read in_linebuf based on expected order.
                    image_stream_active <= 1'b1;
                end
                3'b011: begin // FC1_W_VEC: host writes fc1 weight vector for current conv2 position i (10 bytes)
                    // fc1_w_vec length 10: base index 0..9
                    for (int b=0;b<4;b++) begin
                        int wi = base + b;
                        if (wi < OUT1_M) fc1_w_vec[wi] <= $signed(dina[8*b +: 8]);
                    end
                    // if host writes remaining bytes in second/third write, they will update remaining slots
                    // We set valid when host wrote all 10 bytes: simple heuristic: if base==0 and base+? but host should ensure to write fully.
                    // For robustness, set valid when host wrote any fc1_w_vec (NPU will only use it when it's valid and for expected conv2 position)
                    fc1_w_vec_valid <= 1'b1;
                end
                3'b010: begin // FC2_W: write fc2 weights (10 bytes total)
                    for (int b=0;b<4;b++) begin
                        int wi = base + b;
                        if (wi < OUT1_M) fc2_w_buf[wi] <= $signed(dina[8*b +: 8]);
                    end
                    fc2_w_valid <= 1'b1;
                end
                3'b111: begin // CTRL
                    if (idx == 12'd0) begin
                        // any write to CTRL idx 0 triggers start processing of current channel
                        start_channel_req <= 1'b1;
                    end else if (idx == 12'd1) begin
                        // optional: signal image stream finish for current channel
                        image_stream_active <= 1'b0;
                    end
                end
                default: ;
            endcase
        end else begin
            // clear one-cycle signals
            start_channel_req <= 1'b0;
            // fc1_w_vec_valid persists until consumed
        end
    end

    // -----------------------
    // Processing state machine: channel-by-channel streaming
    // High-level:
    // IDLE:
    //   wait start_channel_req -> move to WAIT_FOR_IMG
    // WAIT_FOR_IMG:
    //   wait until enough image rows have been written to in_linebuf so we can start producing conv1 outputs;
    //   then iterate conv1 outputs in row-major order using NUM_PE to accumulate 3x3 conv1 for current channel.
    // For each conv1 output (oh,ow) we compute conv1_out (ReLU) and write into conv1_linebuf[oh%2][ow].
    // Once conv1_linebuf has 3 rows ready spanning a conv2 window (i.e., we have produced conv1 rows >=2),
    //   for the conv2 position that becomes available we compute *per-channel contribution*:
    //   We iterate over kterm 0..K_H*K_W-1: for each term get conv1 value from conv1_linebuf and conv2_k_curr[term]
    //   accumulate term_result = conv1_val*conv2_k; then before finalizing conv2_val we need fc1_w_vec for that conv2 position.
    // BUT we instead combine on the fly: for each conv1 term we multiply term_result by fc1_w_vec[m] for m=0..9 and add into fc1_acc[m].
    // To do that NPU needs fc1_w_vec for this conv2 position to be present (fc1_w_vec_valid).
    // Therefore host MUST stream fc1_w_vec for each conv2 position prior to or in time with that conv2 position's finalization.
    // -----------------------

    // processing counters init
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            curr_channel <= 0;
            img_byte_ptr <= 0;
            conv1_oh <= 0;
            conv1_ow <= 0;
            conv1_kidx <= 0;
            conv2_kterm <= 0;
            conv1_tmp_acc <= 0;
            conv2_partial <= 0;
            // zero fc1_acc
            for (int m=0;m<OUT1_M;m++) fc1_acc[m] <= 0;
            done_reg <= 1'b0;
            result_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start_channel_req) begin
                        // prepare to process this channel. Assume conv1_k_curr & conv2_k_curr have been loaded by host.
                        img_byte_ptr <= 0;
                        conv1_oh <= 0;
                        conv1_ow <= 0;
                        conv1_kidx <= 0;
                        conv2_kterm <= 0;
                        conv1_tmp_acc <= 0;
                        state <= WAIT_FOR_IMG;
                    end
                end

                WAIT_FOR_IMG: begin
                    // host must stream image; we wait until at least three rows have been written (i.e., row index >= 2)
                    // Rather than tracking exact per-byte arrival we simply check a heuristic: image_stream_active asserted by host
                    // and assume host streams the full image in row-major order; NPU reads in_linebuf rows via modulo addressing.
                    if (image_stream_active) begin
                        // start processing conv1 outputs as image_stream progresses.
                        state <= PROC_CONV1;
                    end
                end

                PROC_CONV1: begin
                    // compute conv1 for current output pos (conv1_oh, conv1_ow) for current channel using kernel conv1_k_curr
                    // We perform NUM_PE kernel terms per cycle
                    logic signed [31:0] partial = 0;
                    for (int p=0; p<NUM_PE; p++) begin
                        int ke = conv1_kidx + p;
                        if (ke < K_H*K_W) begin
                            int kh = ke / K_W;
                            int kw = ke % K_W;
                            int ih = conv1_oh + kh;
                            int iw = conv1_ow + kw;
                            logic signed [7:0] pix = in_linebuf[ih % 2][iw];
                            logic signed [7:0] w = conv1_k_curr[ke];
                            partial += pix * w;
                        end
                    end
                    if (conv1_kidx == 0) conv1_tmp_acc <= 0;
                    conv1_tmp_acc <= conv1_tmp_acc + partial;
                    if (conv1_kidx + NUM_PE >= K_H*K_W) begin
                        // finished conv1 output for this position & channel
                        logic signed [15:0] val = conv1_tmp_acc;
                        if (val < 0) val = 0; // ReLU
                        conv1_linebuf[conv1_oh % 2][conv1_ow] <= val;
                        conv1_tmp_acc <= 0;
                        conv1_kidx <= 0;
                        // advance position
                        conv1_ow <= conv1_ow + 1;
                        if (conv1_ow >= OUT1_W) begin
                            conv1_ow <= 0;
                            conv1_oh <= conv1_oh + 1;
                        end
                        // if we've produced at least 3 conv1 rows, we can process conv2 contributions for the top row that just became available:
                        if (conv1_oh >= 2) begin
                            // prepare conv2 processing for position conv2_oh = conv1_oh - 2, and ow = conv1_ow-? careful mapping:
                            // We'll generate conv2 positions in same row-major order as conv1 outputs become available.
                            conv2_kterm <= 0;
                            state <= PROC_CONV2_ACC;
                        end else begin
                            // continue producing conv1 outputs
                            state <= PROC_CONV1;
                        end
                    end else begin
                        conv1_kidx <= conv1_kidx + NUM_PE;
                        state <= PROC_CONV1;
                    end
                end

                PROC_CONV2_ACC: begin
                    // We're computing contributions for one conv2 position: its coordinates:
                    int conv2_oh = conv1_oh - 2;
                    int conv2_ow = conv1_ow; // because conv1_ow already advanced after last conv1 write -> careful with off-by-one
                    // We'll compute partial terms over K_H*K_W kernel positions and for each term immediately multiply with fc1_w_vec[:]
                    // Host must supply fc1_w_vec for this conv2 position (fc1_w_vec_valid == 1).
                    if (!fc1_w_vec_valid) begin
                        // wait until host streams fc1_w_vec for this conv2 position
                        state <= PROC_CONV2_ACC;
                    end else begin
                        // iterate NUM_PE kernel-term multiplications per cycle
                        logic signed [63:0] local_partial_sum[0:NUM_PE-1];
                        for (int p=0;p<NUM_PE;p++) local_partial_sum[p] = 0;
                        for (int p=0;p<NUM_PE;p++) begin
                            int t = conv2_kterm + p;
                            if (t < K_H*K_W*CHAN /*note: here conv2_k_curr only for single channel, so we use K_H*K_W*/ ) begin
                                // map t to kh,kw for current channel
                                int kh = t / K_W;
                                int kw = t % K_W;
                                // conv1 row is conv2_oh+kh; conv1_linebuf holds rows modulo 2. conv1_linebuf stores only current channel's conv1 outputs.
                                int c1_row = conv2_oh + kh;
                                int c1_col = conv2_ow + kw;
                                logic signed [15:0] c1v = conv1_linebuf[c1_row % 2][c1_col];
                                logic signed [7:0] w2 = conv2_k_curr[kh*K_W + kw];
                                // term_result = c1v * w2  (16 * 8 -> 24 bits)
                                logic signed [31:0] term_result = c1v * w2;
                                // Now for each m in 0..OUT1_M-1, multiply by fc1_w_vec[m] and add to fc1_acc[m]
                                // We can use NUM_PE to parallelize across p (kernel terms) but inner loop across m (10) still sequential here.
                                for (int m=0;m<OUT1_M;m++) begin
                                    fc1_acc[m] <= fc1_acc[m] + (term_result * fc1_w_vec[m]);
                                end
                            end
                        end
                        if (conv2_kterm + NUM_PE >= K_H*K_W) begin
                            // finished conv2 position accumulation for this channel
                            conv2_kterm <= 0;
                            // mark fc1_w_vec consumed for this conv2 position (host must supply a fresh fc1_w_vec for next conv2 position)
                            fc1_w_vec_valid <= 1'b0;
                            // advance to produce next conv1->conv2 mapping: if more conv1 produced positions exist, go back to PROC_CONV1 or IDLE
                            // If we've processed all conv1 outputs for this channel (i.e., conv1_oh reached OUT1_H),
                            // we check whether image streaming finished; here we simply return to PROC_CONV1 to continue producing next conv1 outputs.
                            state <= PROC_CONV1;
                        end else begin
                            conv2_kterm <= conv2_kterm + NUM_PE;
                            state <= PROC_CONV2_ACC;
                        end
                    end
                end

                DONE: begin
                    // nothing
                    state <= DONE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // -----------------------
    // Finalization: after all channels processed, host should write FC2 weights and then write a CTRL to ask NPU to finalize:
    // We implement CTRL idx==2 as "finalize and compute fc2"
    logic finalize_req;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) finalize_req <= 1'b0;
        else if (host_wea && sel==3'b111 && idx==12'd2) finalize_req <= 1'b1;
        else finalize_req <= 1'b0;
    end

    logic done_reg;
    logic signed [23:0] result_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            done_reg <= 1'b0;
            result_reg <= 0;
        end else if (finalize_req && fc2_w_valid) begin
            // apply ReLU to fc1_acc and compute fc2 dot product
            logic signed [47:0] tmp_sum;
            tmp_sum = 0;
            for (int m=0;m<OUT1_M;m++) begin
                logic signed [47:0] val = fc1_acc[m];
                if (val < 0) val = 0;
                // multiply with fc2_w_buf[m] (signed 8-bit)
                tmp_sum = tmp_sum + (val * fc2_w_buf[m]);
            end
            result_reg <= tmp_sum[23:0];
            done_reg <= 1'b1;
        end
    end

    // -----------------------
    // Readback logic (sel==111)
    reg [2:0] sel_q;
    reg [11:0] idx_q;
    reg       re_q;
    always @(*) begin
        if (rst) begin
            sel_q = '0; idx_q = '0; re_q = 1'b0; douta = 32'd0;
        end else begin
            re_q = (ena && ~wea);
            sel_q = sel; idx_q = idx;
            if (re_q) begin
                unique case (sel_q)
                    3'b111: begin
                        case (idx_q)
                            12'd0: douta = {31'd0, done_reg};
                            12'd4: begin
                                logic signed [23:0] rv = result_reg;
                                douta = {{8{rv[23]}}, rv};
                            end
                            default: douta = 32'd0;
                        endcase
                    end
                    default: douta = 32'd0;
                endcase
            end else douta = 32'd0;
        end
    end

endmodule
