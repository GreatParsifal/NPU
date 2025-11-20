
`timescale 1ns/1ps

module accelerator (
    input logic clka,
    input logic wea,
    input logic ena,
    input logic [10:0] addra,
    input logic [31:0] dina,
    output logic [31:0] douta,
    input logic rst_ni //?1?0?reset?
);
    // ?
    integer LS_index, US_index;
    reg state;
    parameter s_wait = 0 , s_cal = 1;
    reg rst;
    reg [5:0] counter;

    // LRAM 
    //logic [7:0] webL;// wea & csL
    logic [7:0] csL;//ena & addraRAM
    logic [5:0] addressL [7:0];//addra-?
    //logic [31:0] dL [7:0];
    wire [31:0] qL [7:0];//32bit
    //  8 ?? LRAM 

	logic [5:0] addressL_muxed [7:0];
	logic [7:0][5:0] addressL_axi ;
	logic [7:0] csL_muxed;
	logic [7:0] csL_axi;

reg write_done;
    //reg [7:0] webU;
    logic [7:0] csU;
    logic [5:0] addressU [7:0];
    //reg [31:0] dU [7:0];
    wire [31:0] qU [7:0];
logic buffered_ena;
	logic [5:0] addressU_muxed [7:0];
	logic [7:0][5:0] addressU_axi ;
	logic [7:0] csU_muxed;
	logic [7:0] csU_axi;

	//logic [31:0] dout_d;

	logic [10:0] buffered_addra;
	logic [31:0] sum_out;
	always_comb begin
		csL_axi = '0;
		addressL_axi = '0;
		if(addra < 288) begin
			csL_axi[addra/36] = ena;
		end		
		for (int i=0; i< 8;i=i+1) begin
			addressL_axi[i] = addra % 36;
			addressL_muxed[i] = ena ? addressL_axi[i] : addressL[i];
			csL_muxed[i] = ena ? csL_axi[i] : csL[i];
		end
		
		csU_axi = '0;
		addressU_axi = '0;
		if(addra >= 288 && addra < 576) begin
			csU_axi[(addra - 288)/36] = ena;
		end		
		for (int i=0; i< 8;i=i+1) begin
			addressU_axi[i] = (addra - 288) % 36;
			addressU_muxed[i] = ena ? addressU_axi[i] : addressU[i];
			csU_muxed[i] = ena ? csU_axi[i] : csU[i];
		end
		
		douta = 0;
		if(buffered_ena)begin
		if(buffered_addra < 288) begin
			douta = qL[addra/36];		
		end
		if((buffered_addra >= 288) && (buffered_addra < 576)) begin
			douta = qU[(addra-288)/36];
		end
		if((buffered_addra > 576) && (buffered_addra <= 1600)) begin
			douta = sum_out;	
		end	
		if( buffered_addra == 576) begin
			douta = write_done;
		end
		end
	end
	
	
    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_0 (
        .clk(clka),
        .address(addressL_muxed[0]),
        .cs(csL_muxed[0]),
        .web(~wea),
        .d(dina),
        .q(qL[0])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_1 (
        .clk(clka),
        .address(addressL_muxed[1]),
        .cs(csL_muxed[1]),
        .web(~wea),
        .d(dina),
        .q(qL[1])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_2 (
        .clk(clka),
        .address(addressL_muxed[2]),
        .cs(csL_muxed[2]),
        .web(~wea),
        .d(dina),
        .q(qL[2])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_3 (
        .clk(clka),
        .address(addressL_muxed[3]),
        .cs(csL_muxed[3]),
        .web(~wea),
        .d(dina),
        .q(qL[3])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_4 (
        .clk(clka),
        .address(addressL_muxed[4]),
        .cs(csL_muxed[4]),
        .web(~wea),
        .d(dina),
        .q(qL[4])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_5 (
        .clk(clka),
        .address(addressL_muxed[5]),
        .cs(csL_muxed[5]),
        .web(~wea),
        .d(dina),
        .q(qL[5])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_6 (
        .clk(clka),
        .address(addressL_muxed[6]),
        .cs(csL_muxed[6]),
        .web(~wea),
        .d(dina),
        .q(qL[6])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_7 (
        .clk(clka),
        .address(addressL_muxed[7]),
        .cs(csL_muxed[7]),
        .web(~wea),
        .d(dina),
        .q(qL[7])
    );

    // URAM  


    //  8 ?? URAM 
    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_8 (
        .clk(clka),
        .address(addressU_muxed[0]),
        .cs(csU_muxed[0]),
        .web(~wea),
        .d(dina),
        .q(qU[0])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_9 (
        .clk(clka),
        .address(addressU_muxed[1]),
        .cs(csU_muxed[1]),
        .web(~wea),
        .d(dina),
        .q(qU[1])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_10 (
        .clk(clka),
        .address(addressU_muxed[2]),
        .cs(csU_muxed[2]),
        .web(~wea),
        .d(dina),
        .q(qU[2])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_11 (
        .clk(clka),
        .address(addressU_muxed[3]),
        .cs(csU_muxed[3]),
        .web(~wea),
        .d(dina),
        .q(qU[3])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_12 (
        .clk(clka),
        .address(addressU_muxed[4]),
        .cs(csU_muxed[4]),
        .web(~wea),
        .d(dina),
        .q(qU[4])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_13 (
        .clk(clka),
        .address(addressU_muxed[5]),
        .cs(csU_muxed[5]),
        .web(~wea),
        .d(dina),
        .q(qU[5])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_14 (
        .clk(clka),
        .address(addressU_muxed[6]),
        .cs(csU_muxed[6]),
        .web(~wea),
        .d(dina),
        .q(qU[6])
    );

    ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) ram_instance_15 (
        .clk(clka),
        .address(addressU_muxed[7]),
        .cs(csU_muxed[7]),
        .web(~wea),
        .d(dina),
        .q(qU[7])
    );


    //PE??
wire [7:0] rights [31:0][31:0];
wire [7:0] downs [31:0][31:0];
wire [15:0] sums [31:0][31:0];

reg comp_enb; 

reg comp_done;

    always_ff @(posedge clka) begin
        if (!rst_ni) begin
            write_done <= 0;
            comp_done <= 0;
            comp_enb <= 1;
            rst <= 1;
            //webL <= 8'b11111111;
            //webU <= 8'b11111111; 
            csL <= 8'b00000000;
            csU <= 8'b00000000;
			buffered_addra <= '0; 

            for (LS_index = 0 ; LS_index < 8 ; LS_index = LS_index + 1) begin
                addressL[LS_index] <= 0;
                //dL[LS_index] <= 0;
            end

            for (US_index = 0 ; US_index < 8 ; US_index = US_index + 1) begin
                addressU[US_index] <= 0;
                //dU[US_index] <= 0;
            end
            counter <= 0;
            state <= 0;
			sum_out <= 0;
			buffered_ena <= 0;
        end
        else
			buffered_addra <= addra;
			buffered_ena <= ena;
           	if (ena && ((addra > 576) && (addra <= 1600))) begin
                sum_out <= {16'd0, sums[(addra - 577) / 32][((addra - 577) % 32) ]};
            end
			if (wea && (!write_done)) begin
                rst <= 1;
                if (addra == 576) write_done <= dina[0];
                /*if (addra < 288) begin
                    for (LS_index = 0 ; LS_index < 8 ; LS_index = LS_index + 1) begin
                        if (LS_index == addra / 36) begin
                            addressL[LS_index] <= addra % 36;
                            csL[LS_index] <= ena;
                            webL[LS_index] <= ~(ena & wea);
                            dL[LS_index] <= dina;
                        end
                        else begin
                            addressL[LS_index] <= 0;
                            csL[LS_index] <= 0;
                            webL[LS_index] <= 1;
                        end
                    end
                end
                if (addra >= 288 && addra < 576) begin
                    for (US_index = 0 ; US_index < 8 ; US_index = US_index + 1) begin
                        if (US_index ==(addra - 288) / 36) begin
                            addressU[US_index] <= (addra - 288) % 36;
                            csU[US_index] <= ena;
                            webU[US_index] <= ~(ena & wea);
                            dU[US_index] <= dina;
                        end
                        else begin
                            addressU[US_index] <= 0;
                            csU[US_index] <= 0;
                            webU[US_index] <= 1;
                        end
                    end
                end*/
            end
            else
                if (write_done && (!comp_done)) begin
                    if(comp_enb == 1) begin 
                        state <= s_wait;
                        rst <= 1;
                        comp_enb <= 0;
                    end
                    else begin
                        case(state)
                            s_wait: begin
                                if(comp_enb == 0) begin
                                    state <= s_cal;
                                    rst <= 1;
                                    counter <= 0;
                                    //webL <= 8'b11111111;
                                    //webU <= 8'b11111111; 
                                    csL <= 8'b11111111;
                                    csU <= 8'b11111111; 
                                    for (LS_index = 0 ; LS_index < 8 ; LS_index = LS_index + 1) begin
                                        addressL[LS_index] <= 0;
                                    end

                                    for (US_index = 0 ; US_index < 8 ; US_index = US_index + 1) begin
                                        addressU[US_index] <= 0;
                                    end
                                end
                            end

                            s_cal: begin
                                if(counter < 41) begin
                                    rst <= 0;
                                    counter <= counter + 1;
                                    for (LS_index = 0 ; LS_index < 8 ; LS_index = LS_index + 1) begin
                                        addressL[LS_index] <= counter;
                                    end

                                    for (US_index = 0 ; US_index < 8 ; US_index = US_index + 1) begin
                                        addressU[US_index] <= counter;
                                    end
                                end else begin
                                    comp_done <= 1;
                                end
                            end

                    endcase
                end
            end
               
    end
    
    // PE????

    genvar row, col, PE_index;
    generate
    for (PE_index = 0; PE_index < 64; PE_index = PE_index + 1) begin : gen_PEs
        for (row = 0; row < 4; row = row + 1) begin : gen_row
            for (col = 0; col < 4; col = col + 1) begin : gen_col

                if (row == 0 && col == 0) begin
                    PE pe00 (.clk(clka), .rst(rst), .left(qL[PE_index/8][31:24]), .up(qU[PE_index%8][31:24]), .right(rights[PE_index/8*4][PE_index%8*4]), .down(downs[PE_index/8*4][PE_index%8*4]), .sum_out(sums[PE_index/8*4][PE_index%8*4]));
                end
                else if (row == 0) begin
                    PE pe (.clk(clka), .rst(rst), .left(rights[PE_index/8*4][PE_index%8*4+col-1]), .up(qU[PE_index%8][31-8*col:24-8*col]), .right(rights[PE_index/8*4][PE_index%8*4+col]), .down(downs[PE_index/8*4][PE_index%8*4+col]), .sum_out(sums[PE_index/8*4][PE_index%8*4+col]));
                end
                else if (col == 0) begin
                    PE pe (.clk(clka), .rst(rst), .left(qL[PE_index/8][31-8*row:24-8*row]), .up(downs[PE_index/8*4+row-1][PE_index%8*4]), .right(rights[PE_index/8*4+row][PE_index%8*4]), .down(downs[PE_index/8*4+row][PE_index%8*4]), .sum_out(sums[PE_index/8*4+row][PE_index%8*4]));
                end
                else begin
                    PE pe (.clk(clka), .rst(rst), .left(rights[PE_index/8*4+row][PE_index%8*4+col-1]), .up(downs[PE_index/8*4+row-1][PE_index%8*4+col]), .right(rights[PE_index/8*4+row][PE_index%8*4+col]), .down(downs[PE_index/8*4+row][PE_index%8*4+col]), .sum_out(sums[PE_index/8*4+row][PE_index%8*4+col]));
                end
            end
        end
    end
endgenerate

endmodule
