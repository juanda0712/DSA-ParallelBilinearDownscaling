module connect(
    input  logic        tck,
    input  logic        tdi,
    input  logic        aclr,
    input  logic [1:0]  ir_in,
    input  logic        v_sdr,
    input  logic        v_udr,
    input  logic        v_cdr,
    input  logic        v_uir,

    // LEDs y switches originales
    input  logic [3:0]  switches,
    output logic        tdo,
    output logic [7:0]  leds,

    // Señales nuevas hacia la memoria
    output logic        mem_we,
    output logic [7:0]  mem_addr,
    output logic [7:0]  mem_data_in,
    input  logic [7:0]  mem_data_out
);

    // Instrucciones JTAG
    typedef enum logic [1:0] {
        BYPASS = 2'b00,
        DIP    = 2'b01,
        LED    = 2'b10,
        MEM    = 2'b11
    } jtag_instr_e;

    jtag_instr_e current_instr;
    assign current_instr = jtag_instr_e'(ir_in);

    // Registers
    logic [1:0]  DR0;     // bypass
    logic [7:0]  DR1;     // LED/DIP
    logic [15:0] DR_MEM;  // memory access

    logic [7:0] led_output_reg;

    assign leds = led_output_reg;

    // Memory interface decode
    assign mem_addr     = DR_MEM[15:8];
    assign mem_data_in  = DR_MEM[7:0];
    assign mem_we       = (current_instr == MEM) && v_udr;

    // TDO mux
    always_comb begin
        case (current_instr)
            BYPASS: tdo = DR0[0];
            DIP,
            LED:    tdo = DR1[0];
            MEM:    tdo = DR_MEM[0];
            default: tdo = DR0[0];
        endcase
    end

    // Shifting
    always_ff @(posedge tck or negedge aclr) begin
        if (!aclr) begin
            DR0 <= '0;
            DR1 <= '0;
            DR_MEM <= 16'h0000;
        end
        else begin
            case (current_instr)

                DIP: begin
                    if (v_cdr)
                        DR1 <= {4'b0000, switches};
                    else if (v_sdr)
                        DR1 <= {tdi, DR1[7:1]};
                end

                LED: begin
                    if (v_sdr)
                        DR1 <= {tdi, DR1[7:1]};
                end

                BYPASS: begin
                    if (v_sdr)
                        DR0 <= {tdi, DR0[1]};
                end

                MEM: begin
                    if (v_sdr)
                        DR_MEM <= {tdi, DR_MEM[15:1]};
                    else if (v_cdr)
                        DR_MEM <= {DR_MEM[15:8], mem_data_out};
                end
            endcase
        end
    end

    // LED output update
    always_ff @(posedge v_udr or negedge aclr) begin
        if (!aclr)
            led_output_reg <= '0;
        else if (current_instr == LED)
            led_output_reg <= DR1;
    end

endmodule
