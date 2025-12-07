module pack (
    input logic clk,
    input logic rst_n,
    input logic pixel_valid,
    input logic save_done,
    input logic [7:0] pix_addr,
    input logic [7:0] in_data,
    output logic save_done_sim,
    output logic pack_valid,
    output logic [31:0] pack_out_data
);

// pix_count logic
logic [1:0] pix_count;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pix_count <= 2'd0;
    end else begin
        case (pix_count)
            2'd0: pix_count <= pixel_valid ? 2'd1 : 2'd0;
            2'd1: begin if (pix_addr == 8'd181) // last pixel addr
                    pix_count <= 2'd0;
                end else begin
                    pix_count <= pixel_valid ? 2'd2 : 2'd1;
                end
            2'd2: pix_count <= pixel_valid ? 2'd3 : 2'd2;
            2'd3: pix_count <= save_done ? 2'd0 : 2'd3;
            default: pix_count <= 2'd0;
        endcase
    end
end

// pack_valid logic
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pack_valid <= 1'b0;
    end else begin
        if (pix_addr == 8'd181 && pixel_valid) begin
            pack_valid <= save_done ? 1'b0 : 1'b1;
        end else if (pix_count == 2'd3) begin
            pack_valid <= save_done ? 1'b0 : 1'b1;
        end
    end
end

// save_done_sim logic
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        save_done_sim <= 1'b0;
    end else begin
        if (pix_count < 2'd3) begin
            save_done_sim <= pixel_valid ? 1'b1: 1'b0;
        end else begin
            save_done_sim <= save_done ? 1'b1 : 1'b0;
        end
    end
end

// pack_out_data logic
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pack_out_data <= 32'd0;
    end else begin
        case (pix_count)
            2'd0: pack_out_data[7:0] <= in_data;
            2'd1: pack_out_data[15:8] <= in_data;
            2'd2: pack_out_data[23:16] <= in_data;
            2'd3: pack_out_data[31:24] <= in_data;
            default: pack_out_data <= 32'd0;
        endcase
    end
end

endmodule