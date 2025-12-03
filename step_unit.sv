module step_unit(
    input  logic        clk,
    input  logic        aclr,
    input  logic [7:0]  reg_f9,
    output logic        step_mode,
    output logic        step_pulse,
    output logic        auto_step_pulse
);

    // Modo paso-a-paso
    assign step_mode = reg_f9[1];

    // Pulso manual inmediato (reg_f9[0] = 1)
    assign step_pulse = reg_f9[0];

    // Pulso automático interno si se desea
    assign auto_step_pulse = reg_f9[1] & reg_f9[0];

endmodule
