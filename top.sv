// top_with_control.sv
module top (
    input  logic CLOCK_50,
    input  logic reset_n
);

    // ---- Señales JTAG ----
    logic tck;
    logic tdi;
    logic tdo;
    logic [2:0] ir_in;
    logic [2:0] ir_out;
    logic v_cdr, v_sdr, v_udr, v_uir;
    logic v_e1dr, v_e2dr, v_pdr, v_cir;

    // ---- Mem interface ----
    logic mem_we;
    logic [7:0] mem_addr;
    logic [7:0] mem_data_in;
    logic [7:0] mem_data_out;

    // ---- Señales de control / observabilidad ----
    logic step_mode;
    logic step_pulse;
    logic start_proc_pulse;
    logic busy_jtag;
    logic done_jtag;

    // ---- Señales de control_unit (separadas para debug) ----
    logic busy_ctrl;
    logic done_ctrl;

    // ---- Instancia Virtual JTAG ----
    vJtag vjtag_inst (
        .tdo(tdo),
        .tdi(tdi),
        .tck(tck),
        .ir_in(ir_in),
        .ir_out(ir_out),
        .virtual_state_cdr(v_cdr),
        .virtual_state_sdr(v_sdr),
        .virtual_state_e1dr(v_e1dr),
        .virtual_state_pdr(v_pdr),
        .virtual_state_e2dr(v_e2dr),
        .virtual_state_udr(v_udr),
        .virtual_state_cir(v_cir),
        .virtual_state_uir(v_uir)
    );

    // ---- Instancia connect (tu JTAG front-end, sin modificaciones) ----
    connect jtag_unit (
        .tck(tck),
        .tdi(tdi),
        .aclr(reset_n),
        .ir_in(ir_in),
        .v_sdr(v_sdr),
        .v_udr(v_udr),
        .v_cdr(v_cdr),
        .v_uir(v_uir),
        .tdo(tdo),

        // Mem interface
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_data_in(mem_data_in),
        .mem_data_out(mem_data_out),

        // STEP outputs (provienen del regfile / stepping unit dentro de connect)
        .step_mode(step_mode),
        .step_pulse(step_pulse),

        // Observabilidad del regfile (no usaremos para el control unit, pero quedan disponibles)
        .start_proc_pulse(start_proc_pulse),
        .busy(busy_jtag),
        .done(done_jtag)
    );

    // ---- Instancia control_unit (Fase 3) ----
    // Usar CLOCK_50 como reloj aquí para que no dependa del TCK (TCK es JTAG clock, mejor usar CLOCK_50)
    // Ajusta CYCLES según necesites o conéctalo a width*height en iteraciones posteriores.
    control_unit #(.CYCLES(200)) cu_inst (
        .clk(CLOCK_50),
        .aclr_n(reset_n),
        .start_proc_pulse(start_proc_pulse),
        .step_mode(step_mode),
        .step_pulse(step_pulse),
        .busy(busy_ctrl),
        .done(done_ctrl)
    );

    // ---- Memoria simple ----
    mem_sram_simple #(.ADDR_BITS(8)) RAM0 (
        .clk(CLOCK_50),
        .we(mem_we),
        .addr(mem_addr),
        .data_in(mem_data_in),
        .data_out(mem_data_out)
    );

    // ---- Debug / LEDs (opcional) ----
    // Si quieres conectar a pines físicos, conecta busy_ctrl / done_ctrl aquí
    // wire led_busy = busy_ctrl;
    // wire led_done = done_ctrl;

endmodule
