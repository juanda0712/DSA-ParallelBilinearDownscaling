module top (
    input  logic CLOCK_50,
    input  logic reset_n,

    input  logic [3:0] SW,
    output logic [7:0] LEDR
);

    // Señales JTAG
    logic        tck;
    logic        tdi;
    logic        tdo;
    logic [1:0]  ir_in;
    logic [1:0]  ir_out;
    logic        virtual_state_cdr;
    logic        virtual_state_sdr;
    logic        virtual_state_udr;
    logic        virtual_state_uir;
    logic        virtual_state_e1dr, virtual_state_e2dr, virtual_state_pdr, virtual_state_cir;

    // Señales memoria
    logic        mem_we;
    logic [7:0]  mem_addr;
    logic [7:0]  mem_data_in;
    logic [7:0]  mem_data_out;

    // --- Instancia del IP Virtual JTAG ---
    vJtag vjtag_inst (
        .tdo(tdo),
        .tdi(tdi),
        .tck(tck),
        .ir_in(ir_in),
        .ir_out(ir_out),
        .virtual_state_cdr(virtual_state_cdr),
        .virtual_state_sdr(virtual_state_sdr),
        .virtual_state_e1dr(virtual_state_e1dr),
        .virtual_state_pdr(virtual_state_pdr),
        .virtual_state_e2dr(virtual_state_e2dr),
        .virtual_state_udr(virtual_state_udr),
        .virtual_state_cir(virtual_state_cir),
        .virtual_state_uir(virtual_state_uir)
    );

    // --- Instancia del módulo connect ---
    connect jtag_interface (
        .tck(tck),
        .tdi(tdi),
        .aclr(reset_n),
        .ir_in(ir_in),
        .v_sdr(virtual_state_sdr),
        .v_udr(virtual_state_udr),
        .v_cdr(virtual_state_cdr),
        .v_uir(virtual_state_uir),

        .switches(SW),
        .tdo(tdo),
        .leds(LEDR),

        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_data_in(mem_data_in),
        .mem_data_out(mem_data_out)
    );

    // --- Instancia de memoria ---
    mem_sram_simple #(.ADDR_BITS(8)) memory0 (
        .clk(CLOCK_50),
        .we(mem_we),
        .addr(mem_addr),
        .data_in(mem_data_in),
        .data_out(mem_data_out)
    );

endmodule
