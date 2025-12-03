module connect(
    input  logic        tck,
    input  logic        tdi,
    input  logic        aclr,
    input  logic [1:0]  ir_in,
    input  logic        v_sdr,
    input  logic        v_udr,
    input  logic        v_cdr,
    input  logic        v_uir,

    output logic        tdo,

    // Mem interface
    output logic        mem_we,
    output logic [7:0]  mem_addr,
    output logic [7:0]  mem_data_in,
    input  logic [7:0]  mem_data_out
);

    // -------------------------------
    //  INSTRUCCIONES JTAG
    // -------------------------------
    typedef enum logic [1:0] {
        BYPASS = 2'b00,
        IR     = 2'b01,
        MEM    = 2'b11
    } jtag_instr_e;

    jtag_instr_e current_instr;
    assign current_instr = jtag_instr_e'(ir_in);

    // -------------------------------
    //  DR REGISTERS
    // -------------------------------
    logic [1:0]  DR0;         // BYPASS
    logic [15:0] DR_MEM;      // [15:8] addr, [7:0] data
    logic [15:0] DR_IR;       // [15:12] unused, [11:8] index, [7:0] value

    // -------------------------------
    //  MEM signals
    // -------------------------------
    assign mem_addr    = DR_MEM[15:8];
    assign mem_data_in = DR_MEM[7:0];
    assign mem_we      = (current_instr == MEM) && v_udr;

    // -------------------------------
    //  REGFILE
    // -------------------------------
    logic [7:0] regfile [0:15];
    integer ii;

    // -------------------------------
    //  TDO MUX
    // -------------------------------
    always_comb begin
        case (current_instr)
            BYPASS: tdo = DR0[0];
            MEM:    tdo = DR_MEM[0];
            IR:     tdo = DR_IR[0];
            default: tdo = 1'b0;
        endcase
    end

    // -------------------------------
    //  SHIFT & CAPTURE
    // -------------------------------
    always_ff @(posedge tck or negedge aclr) begin
        if (!aclr) begin
            DR0    <= '0;
            DR_MEM <= 16'h0000;
            DR_IR  <= 16'h0000;
        end
        else begin
            case (current_instr)

                // ---------------- BYPASS ----------------
                BYPASS: begin
                    if (v_sdr)
                        DR0 <= {tdi, DR0[1]};
                end

                // ---------------- MEM ----------------
                MEM: begin
                    if (v_sdr)
                        DR_MEM <= {tdi, DR_MEM[15:1]};
                    else if (v_cdr)
                        DR_MEM <= {DR_MEM[15:8], mem_data_out};
                end

                // ---------------- IR (REGISTROS) ----------------
                IR: begin
                    if (v_sdr)
                        DR_IR <= {tdi, DR_IR[15:1]};
                    else if (v_cdr)
                        DR_IR <= {DR_IR[15:8], regfile[DR_IR[11:8]]};
                end

            endcase
        end
    end

    // -------------------------------
    //  UPDATE (solo acciones)
    // -------------------------------
    always_ff @(posedge v_udr or negedge aclr) begin
        if (!aclr) begin
            for (ii = 0; ii < 16; ii++)
                regfile[ii] <= 8'h00;
        end
        else begin
            case (current_instr)

                // WRITE REG
                IR: begin
                    regfile[DR_IR[11:8]] <= DR_IR[7:0];
                end

                // WRITE MEM: ya lo hace mem_we

            endcase
        end
    end

endmodule
