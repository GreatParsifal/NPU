`include "axi/typedef.svh"
`include "axi/assign.svh"

module cv32e40p_xilinx (
    input   logic   clk_i,
    input   logic   rst_ni,
    input   logic   tck_i,
    input   logic   tms_i,
    input   logic   td_i,
    output  logic   td_o,
    output  logic   clk_led,
    output  logic   tck_led
);
    /*logic clk_i;
    always_ff @(posedge fpga_clk_i) begin 
        if(~rst_ni) begin
            clk_i <= 0;
        end
        else begin
        clk_i <= ~clk_i;
        end
    end*/

    logic ndmreset;
    logic ndmreset_n;

    rstgen i_rstgen_main (
        .clk_i        ( clk_i                      ),
        .rst_ni       ( rst_ni & (~ndmreset) ),
        .test_mode_i  ( 1'b0                  ),
        .rst_no       ( ndmreset_n               ),
        .init_no      (                          ) // keep open
    );


    AXI_BUS #(
        .AXI_ADDR_WIDTH ( 32    ),
        .AXI_DATA_WIDTH ( 32    ),
        .AXI_ID_WIDTH   ( 2     ),
        .AXI_USER_WIDTH ( 1     )
    ) slave[2:0]();

    AXI_BUS #(
        .AXI_ADDR_WIDTH ( 32    ),
        .AXI_DATA_WIDTH ( 32    ),
        .AXI_ID_WIDTH   ( 4     ),
        .AXI_USER_WIDTH ( 1     )
    ) master[3:0]();//new slave: accelerator

    
    localparam axi_pkg::xbar_cfg_t AXI_XBAR_CFG = '{
        NoSlvPorts:         3,
        NoMstPorts:         4, // new slave: accelerator
        MaxMstTrans:        1, // Probably requires update
        MaxSlvTrans:        1, // Probably requires update
        FallThrough:        1'b0,
        LatencyMode:        axi_pkg::CUT_ALL_PORTS,
        AxiIdWidthSlvPorts: 2,
        AxiIdUsedSlvPorts:  2,
        UniqueIds:          1'b0,
        AxiAddrWidth:       32,
        AxiDataWidth:       32,
        //NoAddrRules:        4  // new slave: accelerator
        NoAddrRules:        5  // split SRAM into I/D two ranges
    };

    //axi_pkg::xbar_rule_32_t [3:0] addr_map;
    axi_pkg::xbar_rule_32_t [4:0] addr_map;

    localparam idx_rom      = 0;
    localparam idx_sram     = 1;
    localparam idx_acc      = 3;// new slave: accelerator
    localparam rom_base     = 32'h00010000;
    localparam rom_length   = 32'h00010000;
    // localparam sram_base    = 32'h80000000;
    // localparam sram_length  = 32'h10000000;
    localparam isram_base   = 32'h8000_0000;  // instruction area
    localparam isram_length = 32'h0000_0800;  // 2KB
    localparam dsram_base   = 32'h8000_0800;  // data area
    localparam dsram_length = 32'h0000_1800;  // 6KB
    localparam acc_base     = 32'h70000000;// new slave: accelerator
    localparam acc_length   = 32'h10000000;// new slave: accelerator

    /* assign addr_map = '{
        '{ idx: idx_rom,       start_addr: rom_base,        end_addr: rom_base + rom_length   },
        '{ idx: idx_sram,      start_addr: sram_base,       end_addr: sram_base + sram_length },
        '{ idx: 2,             start_addr: 32'h0000_0000,   end_addr: 32'h00001000            },
        '{ idx: idx_acc,      start_addr: acc_base,       end_addr: acc_base + acc_length }
    }; */

    assign addr_map = '{
        '{ idx: idx_rom,    start_addr: rom_base,     end_addr: rom_base  + rom_length   },
        // I-SRAM window -> same target idx_sram
        '{ idx: idx_sram,   start_addr: isram_base,   end_addr: isram_base + isram_length},
        // D-SRAM window -> same target idx_sram
        '{ idx: idx_sram,   start_addr: dsram_base,   end_addr: dsram_base + dsram_length},
        // Debug module window
        '{ idx: 2,          start_addr: 32'h0000_0000,end_addr: 32'h0000_1000           },
        '{ idx: idx_acc,    start_addr: acc_base,     end_addr: acc_base  + acc_length   }
    };

    axi_xbar_intf #(
        .AXI_USER_WIDTH ( 1                         ),
        .Cfg            ( AXI_XBAR_CFG              ),
        .rule_t         ( axi_pkg::xbar_rule_32_t   )
    ) i_axi_xbar (
        .clk_i                 ( clk_i      ),
        .rst_ni                ( ndmreset_n ),
        .test_i                ( 1'b0       ),
        .slv_ports             ( slave      ),
        .mst_ports             ( master     ),
        .addr_map_i            ( addr_map   ),
        .en_default_mst_port_i ( '0         ),
        .default_mst_port_i    ( '0         )
    );

    logic           instr_req;
    logic           instr_gnt;
    logic           instr_rvalid;
    logic [31:0]    instr_addr;
    logic [31:0]    instr_rdata;
    logic           data_req;
    logic           data_gnt;
    logic           data_rvalid;
    logic           data_we;
    logic [3:0]     data_be;
    logic [31:0]    data_addr;
    logic [31:0]    data_wdata;
    logic [31:0]    data_rdata;
    logic           data_valid;
    logic           debug_req_valid;
    logic           debug_req_ready;
    dm::dmi_req_t   debug_req;
    logic           debug_resp_valid;
    logic           debug_resp_ready;
    dm::dmi_resp_t  debug_resp;
    logic           debug_req_irq;

    cv32e40p_top #(
        .COREV_PULP(0),
        .COREV_CLUSTER(0),
        .FPU(0),
        .FPU_ADDMUL_LAT(0),
        .FPU_OTHERS_LAT(0),
        .ZFINX(0),
        .NUM_MHPMCOUNTERS(0) 
    )   i_ri5cy (
        .clk_i                  (clk_i          ),
        .rst_ni                 (ndmreset_n     ),
        .pulp_clock_en_i        ('0             ),
        .scan_cg_en_i           ('0             ),
        .boot_addr_i            (32'h00010000   ),
        .mtvec_addr_i           (32'h00010000   ),
        .dm_halt_addr_i         (32'h00000800   ),
        .hart_id_i              ('0             ),
        .dm_exception_addr_i    (32'h00010000   ),
        .instr_req_o            (instr_req      ),
        .instr_gnt_i            (instr_gnt      ),
        .instr_rvalid_i         (instr_rvalid   ),
        .instr_addr_o           (instr_addr     ),
        .instr_rdata_i          (instr_rdata    ),
        .data_req_o             (data_req       ),
        .data_gnt_i             (data_gnt       ),
        .data_rvalid_i          (data_valid     ),//data_rvalid process both rvalid&wvalid
        .data_we_o              (data_we        ),
        .data_be_o              (data_be        ),
        .data_addr_o            (data_addr      ),
        .data_wdata_o           (data_wdata     ),
        .data_rdata_i           (data_rdata     ),
        .irq_i                  (32'b0          ),
        .irq_ack_o              (               ),
        .irq_id_o               (               ),
        .debug_req_i            (debug_req_irq  ),
        .debug_havereset_o      (               ),
        .debug_running_o        (               ),
        .debug_halted_o         (               ),
        .fetch_enable_i         (1'b1           ),
        .core_sleep_o           (               )
    );

    `AXI_TYPEDEF_ALL(axi        ,
                logic [31:0]    ,
                logic [3:0]     ,
                logic [31:0]    ,
                logic [3:0]     ,
                logic           )

    axi_req_t   instr_axi_req;
    axi_resp_t  instr_axi_resp;

    `AXI_ASSIGN_FROM_REQ(slave[0],instr_axi_req)
    `AXI_ASSIGN_TO_RESP(instr_axi_resp,slave[0])

    axi_adapter #(
        .ADDR_WIDTH         (32         ),
        .DATA_WIDTH         (32         ),
        .AXI_DATA_WIDTH     (32         ),
        .AXI_ID_WIDTH       (4          ),
        .MAX_OUTSTANDING_AW (7          ),
        .axi_req_t          (axi_req_t  ),
        .axi_rsp_t          (axi_resp_t )
    ) i_axi_adapter_instr (
        .clk_i                 ( clk_i          ),
        .rst_ni                ( ndmreset_n     ),
        .req_i                 ( instr_req      ),
        .type_i                ( 1'b0           ),
        .amo_i                 ( 4'b0000        ),
        .gnt_o                 ( instr_gnt      ),
        .addr_i                ( instr_addr     ),
        .we_i                  ( 1'b0           ),
        .wdata_i               ( '0             ),
        .be_i                  ( 4'b1111        ),
        .size_i                ( 2'b10          ),
        .id_i                  ( 4'b0001          ),
        .valid_o               ( instr_rvalid   ),
        .rdata_o               ( instr_rdata    ),
        .id_o                  (                ),
        .critical_word_o       (                ),
        .critical_word_valid_o (                ),
        .axi_req_o             ( instr_axi_req  ),
        .axi_resp_i            ( instr_axi_resp )
    );

    axi_req_t   data_axi_req;
    axi_resp_t  data_axi_resp;

    `AXI_ASSIGN_FROM_REQ(slave[1],data_axi_req)
    `AXI_ASSIGN_TO_RESP(data_axi_resp,slave[1])

    assign data_valid = data_rvalid | data_axi_resp.b_valid;

    axi_adapter #(
        .ADDR_WIDTH         (32         ),
        .DATA_WIDTH         (32         ),
        .AXI_DATA_WIDTH     (32         ),
        .AXI_ID_WIDTH       (4          ),
        .MAX_OUTSTANDING_AW (7          ),
        .axi_req_t          (axi_req_t  ),
        .axi_rsp_t          (axi_resp_t )
    ) i_axi_adapter_data (
        .clk_i                 ( clk_i          ),
        .rst_ni                ( ndmreset_n     ),
        .req_i                 ( data_req       ),
        .type_i                ( 1'b0           ),
        .amo_i                 ( 4'b0000        ),
        .gnt_o                 ( data_gnt       ),
        .addr_i                ( data_addr      ),
        .we_i                  ( data_we        ),
        .wdata_i               ( data_wdata     ),
        .be_i                  ( data_be        ),
        .size_i                ( 2'b10          ),
        .id_i                  ( 4'b0010          ),
        .valid_o               ( data_rvalid    ),
        .rdata_o               ( data_rdata     ),
        .id_o                  (                ),
        .critical_word_o       (                ),
        .critical_word_valid_o (                ),
        .axi_req_o             ( data_axi_req   ),
        .axi_resp_i            ( data_axi_resp  )
    );

    dmi_jtag i_dmi_jtag (
        .clk_i                ( clk_i               ),
        .rst_ni               ( rst_ni              ),
        .dmi_rst_no           (                     ), // keep open
        .testmode_i           ( 1'b0                ),
        .dmi_req_valid_o      ( debug_req_valid     ),
        .dmi_req_ready_i      ( debug_req_ready     ),
        .dmi_req_o            ( debug_req           ),
        .dmi_resp_valid_i     ( debug_resp_valid    ),
        .dmi_resp_ready_o     ( debug_resp_ready    ),
        .dmi_resp_i           ( debug_resp          ),
        .tck_i                ( tck_i               ),
        .tms_i                ( tms_i               ),
        .trst_ni              ( rst_ni             ),
        .td_i                 ( td_i                ),
        .td_o                 ( td_o                ),
        .tdo_oe_o             (                     )
    );

    dm::hartinfo_t hartinfo;
    assign hartinfo = '{
        zero1       : '0,
        nscratch    : 2,
        zero0       : '0,
        dataaccess  : 1'b1,
        datasize    : dm::DataCount,
        dataaddr    : dm::DataAddr
    };

    logic           dm_slave_req;
    logic           dm_slave_we;
    logic [31:0]    dm_slave_addr;
    logic [3:0]     dm_slave_be;
    logic [31:0]    dm_slave_wdata;
    logic [31:0]    dm_slave_rdata;

    logic           dm_master_req;
    logic [31:0]    dm_master_add;
    logic           dm_master_we;
    logic [31:0]    dm_master_wdata;
    logic [3:0]     dm_master_be;
    logic           dm_master_gnt;
    logic           dm_master_r_valid;
    logic [31:0]    dm_master_r_rdata;

    axi2mem #(
        .AXI_ID_WIDTH   ( 4    ),
        .AXI_ADDR_WIDTH ( 32        ),
        .AXI_DATA_WIDTH ( 32        ),
        .AXI_USER_WIDTH ( 1        )
    ) i_dm_axi2mem (
        .clk_i      ( clk_i                       ),
        .rst_ni     ( rst_ni                     ),
        .slave      ( master[2]           ),
        .req_o      ( dm_slave_req              ),
        .we_o       ( dm_slave_we               ),
        .addr_o     ( dm_slave_addr             ),
        .be_o       ( dm_slave_be               ),
        .data_o     ( dm_slave_wdata            ),
        .data_i     ( dm_slave_rdata            )
    );


    dm_top #(
        .NrHarts          ( 1       ),
        .BusWidth         ( 32      ),
        .SelectableHarts  ( 1'b1    )
    ) i_dm_top (
        .clk_i            ( clk_i               ),
        .rst_ni           ( rst_ni              ), // PoR
        .testmode_i       ( 1'b0                ),
        .ndmreset_o       ( ndmreset            ),
        .dmactive_o       (                     ), // active debug session
        .debug_req_o      ( debug_req_irq       ),
        .unavailable_i    ( '0                  ),
        .hartinfo_i       ( hartinfo            ),
        .slave_req_i      ( dm_slave_req        ),
        .slave_we_i       ( dm_slave_we         ),
        .slave_addr_i     ( dm_slave_addr       ),
        .slave_be_i       ( dm_slave_be         ),
        .slave_wdata_i    ( dm_slave_wdata      ),
        .slave_rdata_o    ( dm_slave_rdata      ),
        .master_req_o     ( dm_master_req       ),
        .master_add_o     ( dm_master_add       ),
        .master_we_o      ( dm_master_we        ),
        .master_wdata_o   ( dm_master_wdata     ),
        .master_be_o      ( dm_master_be        ),
        .master_gnt_i     ( dm_master_gnt       ),
        .master_r_valid_i ( dm_master_r_valid   ),
        .master_r_rdata_i ( dm_master_r_rdata   ),
        .dmi_rst_ni       ( rst_ni              ),
        .dmi_req_valid_i  ( debug_req_valid     ),
        .dmi_req_ready_o  ( debug_req_ready     ),
        .dmi_req_i        ( debug_req           ),
        .dmi_resp_valid_o ( debug_resp_valid    ),
        .dmi_resp_ready_i ( debug_resp_ready    ),
        .dmi_resp_o       ( debug_resp          )
    );


    axi_req_t   dm_axi_m_req;
    axi_resp_t  dm_axi_m_resp;

    axi_adapter #(
        .ADDR_WIDTH         (32         ),
        .DATA_WIDTH         (32         ),
        .AXI_DATA_WIDTH     (32         ),
        .AXI_ID_WIDTH       (4          ),
        .MAX_OUTSTANDING_AW (7          ),
        .axi_req_t          (axi_req_t  ),
        .axi_rsp_t          (axi_resp_t )
    ) i_axi_adapter_dm (
        .clk_i                 ( clk_i              ),
        .rst_ni                ( rst_ni             ),
        .req_i                 ( dm_master_req      ),
        .type_i                ( 1'b0               ),
        .amo_i                 ( 4'b0000            ),
        .gnt_o                 ( dm_master_gnt      ),
        .addr_i                ( dm_master_add      ),
        .we_i                  ( dm_master_we       ),
        .wdata_i               ( dm_master_wdata    ),
        .be_i                  ( dm_master_be       ),
        .size_i                ( 2'b10              ),
        .id_i                  ( '0                 ),
        .valid_o               ( dm_master_r_valid  ),
        .rdata_o               ( dm_master_r_rdata  ),
        .id_o                  (                    ),
        .critical_word_o       (                    ),
        .critical_word_valid_o (                    ),
        .axi_req_o             ( dm_axi_m_req       ),
        .axi_resp_i            ( dm_axi_m_resp      )
    );

    `AXI_ASSIGN_FROM_REQ(slave[2], dm_axi_m_req)
    `AXI_ASSIGN_TO_RESP(dm_axi_m_resp, slave[2])

    logic           rom_req;
    logic		rom_we;
    logic [31:0]    rom_addr;
    logic [31:0]	rom_wdata;
    logic [31:0]    rom_rdata;
    
    /*bootrom i_bootrom (
        .clk_i   ( clk_i            ),
        .req_i   ( rom_req          ),
        .addr_i  ( rom_addr[15:0]   ),
        .rdata_o ( rom_rdata        )
    );*/
    
    bootram i_bootram (
	.clk_i	(clk_i		),
	.rst_ni	(rst_ni		),
	.req_i	(rom_req	),
	.wen_i	(rom_we		),
	.addr_i	(rom_addr[5:2]	),
	.data_i	(rom_wdata	),
	.data_o	(rom_rdata	)
    );

    axi2mem #(
        .AXI_ID_WIDTH   ( 4     ),
        .AXI_ADDR_WIDTH ( 32    ),
        .AXI_DATA_WIDTH ( 32    ),
        .AXI_USER_WIDTH ( 1     )
    ) i_axi2rom (
        .clk_i  ( clk_i             ),
        .rst_ni ( ndmreset_n        ),
        .slave  ( master[idx_rom]   ),
        .req_o  ( rom_req           ),
        .we_o   ( rom_we            ),
        .addr_o ( rom_addr          ),
        .be_o   (                   ),
        .data_o ( rom_wdata         ),
        .data_i ( rom_rdata         )
    );

	/*sram #(
		.DATA_WIDTH ( 32 ),
		.USER_EN    ( 0 ),
		.SIM_INIT   ( "file" ),
		.NUM_WORDS  ( 512 )
	) i_sram (
		.clk_i      ( clk_i             ),
		.rst_ni     ( ndmreset_n        ),
		.req_i      ( sram_req               ),
		.we_i       ( sram_be & {4{sram_we}}                 ),
		.addr_i     ( sram_addr[10:2] ),
		.wuser_i    ( '0             ),
		.wdata_i    ( sram_wdata             ),
		.be_i       ( 4'b1111                ),
		.ruser_o    (              ),
		.rdata_o    ( sram_rdata             )
	);*/
	logic           sram_req;
	logic           sram_we;
	logic [31:0]    sram_addr;
	logic [31:0]    sram_wdata;
	logic [3:0]     sram_be;
	logic [31:0]    sram_rdata;
        logic sram_reg;
 	//logic [2:0]		sram_req_bank;
	//logic [2:0][31:0] sram_rdata_bank;
	//logic [1:0]		sram_bank_buf;
	/*always @(posedge clk_i or negedge rst_ni)begin
		if(!rst_ni) begin
			sram_bank_buf <= '0;
		end
		else begin
			sram_bank_buf <= sram_addr[14:13];		
		end
	end
	always_comb begin
		sram_req_bank = '0;
		if(sram_req) begin
			sram_req_bank[sram_addr[14:13]] = 1'b1;
		end
		sram_rdata = sram_rdata_bank[sram_bank_buf];
	end*/

	//genvar i;
	//generate 
	//	for(i = 0; i < 2; i = i + 1) begin
`ifdef SIM
			sram_ff #(
				.AddrWidth(11),
				.DataWidth(32)
			) i_sram (
				.clk_i(clk_i),
				.req_i(1'b1),
				.wen_i(sram_be & {4{sram_we}}),
				.addr_i(sram_addr[12:2]),
				.data_i(sram_wdata),
				.data_o(sram_rdata)
			);
        //assign sram_rdata[i] = sram_reg;
`else
	TS1DA32KX32 i_sram (
		.CLK	(clk_i				),
		.A		(sram_addr[16:2]	),
		.CEB	(~sram_req			),
		.OEB	(1'b0				),
		.GWEB	(1'b1				),
		.BWEB	(~sram_we			),
		.BWB	(~sram_be			),
		.DIN	(sram_wdata			),
		.DOUT	(sram_rdata			)
	);
			
`endif	

	

    axi2mem #(
        .AXI_ID_WIDTH   ( 4     ),
        .AXI_ADDR_WIDTH ( 32    ),
        .AXI_DATA_WIDTH ( 32    ),
        .AXI_USER_WIDTH ( 1     )
    ) i_axi2sram (
        .clk_i  ( clk_i             ),
        .rst_ni ( ndmreset_n        ),
        .slave  ( master[idx_sram]  ),
        .req_o  ( sram_req          ),
        .we_o   ( sram_we           ),
        .addr_o ( sram_addr         ),
        .be_o   ( sram_be           ),
        .data_o ( sram_wdata        ),
        .data_i ( sram_rdata        )
    );

    logic           acc_req;
    logic           acc_we;
    logic [31:0]    acc_addr;
    logic [31:0]    acc_wdata;
    logic [31:0]    acc_rdata;

    accelerator i_acc (
        .clka   (clk_i              ),
        .ena    (acc_req           ),
        .wea    (acc_we   ),
        .addra  (acc_addr[12:2]    ),
        .dina   (acc_wdata         ),
        .douta  (acc_rdata         ),
        .rst_ni (ndmreset_n        )
    );

    axi2mem #(
        .AXI_ID_WIDTH   ( 4     ),
        .AXI_ADDR_WIDTH ( 32    ),
        .AXI_DATA_WIDTH ( 32    ),
        .AXI_USER_WIDTH ( 1     )
    ) i_axi2acc (
        .clk_i  ( clk_i             ),
        .rst_ni ( ndmreset_n        ),
        .slave  ( master[idx_acc]  ),
        .req_o  ( acc_req          ),
        .we_o   ( acc_we           ),
        .addr_o ( acc_addr         ),
        .be_o   (                  ),
        .data_o ( acc_wdata        ),
        .data_i ( acc_rdata        )
    );

    logic [31:0] timer_cnt;
    always @(posedge clk_i or negedge rst_ni)
    begin
        if (!rst_ni)
        begin
            clk_led <= 1'b0;
            timer_cnt <= 32'd0;
        end
        else if (timer_cnt == 32'd99_999_999)
        begin
            clk_led <= ~clk_led;
            timer_cnt <= 32'd0;
        end
        else
        begin
            clk_led <= clk_led;
            timer_cnt <= timer_cnt + 32'd1;
        end
    end

    logic [31:0] timer_cnt_tck;
    always @(posedge tck_i or negedge rst_ni)
    begin
        if (!rst_ni)
        begin
            tck_led <= 1'b0;
            timer_cnt_tck <= 32'd0;
        end
        else if (timer_cnt_tck == 32'd99_999_999)
        begin
            tck_led <= ~tck_led;
            timer_cnt_tck <= 32'd0;
        end
        else
        begin
            tck_led <= tck_led;
            timer_cnt_tck <= timer_cnt_tck + 32'd1;
        end
    end
endmodule