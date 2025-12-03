module top (
    input  logic CLOCK_50,
    input  logic reset_n
);
    // Señales JTAG
    logic tck, tdi, tdo;
    logic [2:0] ir_in;
    logic v_cdr, v_sdr, v_udr, v_uir;

    // Buses de Memoria (16 BITS)
    logic jtag_mem_we, ctrl_mem_we, final_mem_we;
    logic [15:0] jtag_mem_addr, ctrl_mem_addr, final_mem_addr;
    logic [7:0] jtag_mem_data_in, ctrl_mem_data_out, final_mem_data_in;
    logic [7:0] mem_data_out_ram;

    // Control
    logic step_mode, step_pulse, start_proc_pulse, busy_ctrl, done_ctrl;
    logic [15:0] cfg_width, cfg_height, cfg_scale;
    logic [7:0] cfg_mode;

    // JTAG Virtual
    vJtag vjtag_inst (.tdo(tdo), .tdi(tdi), .tck(tck), .ir_in(ir_in), 
        .virtual_state_cdr(v_cdr), .virtual_state_sdr(v_sdr), .virtual_state_udr(v_udr), 
        .virtual_state_uir(v_uir));

    // Connect (CORREGIDO)
    connect jtag_unit (
        .tck(tck), .tdi(tdi), .aclr(reset_n), .ir_in(ir_in),
        .v_sdr(v_sdr), .v_udr(v_udr), .v_cdr(v_cdr), .v_uir(v_uir), .tdo(tdo),
        
        // Memoria
        .mem_we(jtag_mem_we), 
        .mem_addr(jtag_mem_addr),
        .mem_data_in(jtag_mem_data_in), 
        .mem_data_out(mem_data_out_ram),
        
        // Control Outputs
        .step_mode(step_mode), 
        .step_pulse(step_pulse), 
        .start_proc_pulse(start_proc_pulse),
        
        // Status INPUTS (Vienen de la CU)
        .hw_busy(busy_ctrl), 
        .hw_done(done_ctrl), 
        
        // Config Outputs
        .cfg_width(cfg_width), .cfg_height(cfg_height), .cfg_scale(cfg_scale), .cfg_mode(cfg_mode)
    );

    // Unidad de Control
    control_unit #(.CYCLES(200)) cu_inst (
        .clk(CLOCK_50), .aclr_n(reset_n), .start_proc_pulse(start_proc_pulse),
        .step_mode(step_mode), .step_pulse(step_pulse), 
        .busy(busy_ctrl), // OUTPUT de la CU
        .done(done_ctrl)  // OUTPUT de la CU
    );
    
    // Placeholder para señales de memoria de la CU (si aún no las implementas)
    assign ctrl_mem_we = 0;
    assign ctrl_mem_addr = 0;
    assign ctrl_mem_data_out = 0;

    // Mux de Arbitraje
    always_comb begin
        if (busy_ctrl) begin
            final_mem_we = ctrl_mem_we;
            final_mem_addr = ctrl_mem_addr;
            final_mem_data_in = ctrl_mem_data_out;
        end else begin
            final_mem_we = jtag_mem_we;
            final_mem_addr = jtag_mem_addr;
            final_mem_data_in = jtag_mem_data_in;
        end
    end

    // Memoria SRAM
    mem_sram_simple #(.ADDR_BITS(16)) RAM0 (
        .clk(CLOCK_50), .we(final_mem_we), .addr(final_mem_addr), 
        .data_in(final_mem_data_in), .data_out(mem_data_out_ram)
    );

endmodule