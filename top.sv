module top (
    input  logic CLOCK_50,
    input  logic reset_n
);
    // ---- Señales JTAG ----
    logic tck, tdi, tdo;
    logic [2:0] ir_in, ir_out;
    logic v_cdr, v_sdr, v_udr, v_uir, v_e1dr, v_e2dr, v_pdr, v_cir;

    // ---- Interfaz Memoria JTAG ----
    logic jtag_mem_we;
    logic [7:0] jtag_mem_addr;
    logic [7:0] jtag_mem_data_in;

    // ---- Interfaz Memoria Control Unit (Interpolador) ----
    logic ctrl_mem_we;
    logic [15:0] ctrl_mem_addr_full; // Dirección completa de 16 bits
    logic [7:0] ctrl_mem_addr;       // Recortada para la RAM simple de ejemplo
    logic [7:0] ctrl_mem_data_out;   // Dato a escribir

    // ---- Arbitraje de Memoria ----
    logic final_mem_we;
    logic [7:0] final_mem_addr;
    logic [7:0] final_mem_data_in;
    logic [7:0] mem_data_out_ram;

    // ---- Señales de Control ----
    logic step_mode, step_pulse, start_proc_pulse;
    logic busy_jtag, done_jtag;
    logic busy_ctrl, done_ctrl;

    // ---- Configuraciones (Desde Regfile) ----
    logic [15:0] cfg_width, cfg_height, cfg_scale;
    logic [7:0]  cfg_mode;

    // ---- Instancia Virtual JTAG ----
    vJtag vjtag_inst (
        .tdo(tdo), .tdi(tdi), .tck(tck),
        .ir_in(ir_in), .ir_out(ir_out),
        .virtual_state_cdr(v_cdr), .virtual_state_sdr(v_sdr),
        .virtual_state_e1dr(v_e1dr), .virtual_state_pdr(v_pdr),
        .virtual_state_e2dr(v_e2dr), .virtual_state_udr(v_udr),
        .virtual_state_cir(v_cir), .virtual_state_uir(v_uir)
    );

    // ---- Connect (JTAG Front-end) MODIFICADO ----
    connect jtag_unit (
        .tck(tck), .tdi(tdi), .aclr(reset_n),
        .ir_in(ir_in),
        .v_sdr(v_sdr), .v_udr(v_udr), .v_cdr(v_cdr), .v_uir(v_uir),
        .tdo(tdo),
        
        // Mem interface (Source JTAG)
        .mem_we(jtag_mem_we),
        .mem_addr(jtag_mem_addr),
        .mem_data_in(jtag_mem_data_in),
        .mem_data_out(mem_data_out_ram), // Lectura siempre disponible

        .step_mode(step_mode),
        .step_pulse(step_pulse),
        .start_proc_pulse(start_proc_pulse),
        .busy(busy_jtag),
        .done(done_jtag),

        // Nuevas salidas de configuración
        .cfg_width(cfg_width),
        .cfg_height(cfg_height),
        .cfg_scale(cfg_scale),
        .cfg_mode(cfg_mode)
    );

    // ---- Control Unit (Interpolation Engine) REESCRITO ----
    control_unit cu_inst (
        .clk(CLOCK_50),
        .aclr_n(reset_n),
        .start_proc_pulse(start_proc_pulse),
        .step_mode(step_mode),
        .step_pulse(step_pulse),
        
        .cfg_width(cfg_width),
        .cfg_height(cfg_height),
        .cfg_scale(cfg_scale),
        .cfg_mode(cfg_mode),

        .busy(busy_ctrl),
        .done(done_ctrl),

        // Mem interface (Source Control Unit)
        .mem_we(ctrl_mem_we),
        .mem_addr(ctrl_mem_addr_full),
        .mem_data_out(ctrl_mem_data_out),
        .mem_data_in(mem_data_out_ram)
    );

    // ---- Mux de Arbitraje de Memoria ----
    // Si la unidad de control está ocupada (busy_ctrl), ella toma el control de la RAM.
    // Si no, el JTAG tiene el control para leer/escribir.
    assign ctrl_mem_addr = ctrl_mem_addr_full[7:0]; // Ajuste a 8 bits para RAM simple

    always_comb begin
        if (busy_ctrl) begin
            final_mem_we      = ctrl_mem_we;
            final_mem_addr    = ctrl_mem_addr;
            final_mem_data_in = ctrl_mem_data_out;
        end else begin
            final_mem_we      = jtag_mem_we;
            final_mem_addr    = jtag_mem_addr;
            final_mem_data_in = jtag_mem_data_in;
        end
    end

    // ---- Memoria simple ----
    mem_sram_simple #(.ADDR_BITS(8)) RAM0 (
        .clk(CLOCK_50),
        .we(final_mem_we),
        .addr(final_mem_addr),
        .data_in(final_mem_data_in),
        .data_out(mem_data_out_ram)
    );

endmodule
