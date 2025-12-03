module top (
    input  logic CLOCK_50,
    input  logic reset_n
);

    // ---- Señales JTAG ----
    logic        tck;
    logic        tdi;
    logic        tdo;
    logic [1:0]  ir_in;   // AHORA 2 BITS
    logic [1:0]  ir_out;
    logic        v_cdr, v_sdr, v_udr, v_uir;
    logic        v_e1dr, v_e2dr, v_pdr, v_cir;

    // ---- Memoria ----
    logic        mem_we;
    logic [7:0]  mem_addr;
    logic [7:0]  mem_data_in;
    logic [7:0]  mem_data_out;

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

    // ---- Instancia connect ----
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

        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_data_in(mem_data_in),
        .mem_data_out(mem_data_out)
    );

    // ---- Memoria simple ----
    mem_sram_simple #(.ADDR_BITS(8)) RAM0 (
        .clk(CLOCK_50),
        .we(mem_we),
        .addr(mem_addr),
        .data_in(mem_data_in),
        .data_out(mem_data_out)
    );

endmodule
