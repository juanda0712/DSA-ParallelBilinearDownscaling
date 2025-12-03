module status_unit(
    input  logic       clk,
    input  logic       aclr,
    input  logic [7:0] reg_f7,
    output logic       busy,
    output logic       done
);
    assign busy = reg_f7[0];
    assign done = reg_f7[1];
endmodule
