module connect(
    input  logic        tck,
    input  logic        tdi,
    input  logic        aclr,
    input  logic [2:0]  ir_in,
    input  logic        v_sdr,
    input  logic        v_udr,
    input  logic        v_cdr,
    input  logic        v_uir,
    output logic        tdo,

    output logic        mem_we,
    output logic [7:0]  mem_addr,   // Nota: Limitado a 8 bits por tu diseño original
    output logic [7:0]  mem_data_in,
    input  logic [7:0]  mem_data_out,

    // Outputs to datapath
    output logic        step_mode,
    output logic        step_pulse,
    output logic        start_proc_pulse,
    output logic        busy,
    output logic        done,

    // NUEVAS SALIDAS PARA CONFIGURACIÓN (Extraídas del regfile)
    output logic [15:0] cfg_width,
    output logic [15:0] cfg_height,
    output logic [15:0] cfg_scale,
    output logic [7:0]  cfg_mode
);
    typedef enum logic [2:0] { BYPASS=3'b000, IR=3'b001, MEM=3'b011 } jtag_instr_e;
    jtag_instr_e instr;
    assign instr = jtag_instr_e'(ir_in);

    //--------------------------------
    // REGFILE 0xF0 – 0xFF
    //--------------------------------
    logic [7:0] regfile [0:15];
    integer i;

    // DR registers
    logic [2:0]  DR0;
    logic [15:0] DR_MEM;
    logic [15:0] DR_IR;

    //--------------------------------
    // Memory interface
    //--------------------------------
    assign mem_addr    = DR_MEM[15:8];
    assign mem_data_in = DR_MEM[7:0];
    assign mem_we = (instr==MEM && v_udr && DR_MEM[15:8] < 8'hF0);

    //--------------------------------
    // TDO MUX
    //--------------------------------
    always_comb begin
        case(instr)
            BYPASS: tdo = DR0[0];
            MEM:    tdo = DR_MEM[0];
            IR:     tdo = DR_IR[0];
            default:tdo = 1'b0;
        endcase
    end

    //--------------------------------
    // SHIFT + CAPTURE
    //--------------------------------
    always_ff @(posedge tck or negedge aclr) begin
        if(!aclr) begin
            DR0     <= 0;
            DR_MEM  <= 0;
            DR_IR   <= 0;
        end else begin
            case(instr)
                BYPASS: if(v_sdr) DR0 <= {tdi, DR0[2:1]};
                MEM: begin
                    if(v_sdr) DR_MEM <= {tdi, DR_MEM[15:1]};
                    else if(v_cdr) begin
                        if(DR_MEM[15:8] >= 8'hF0)
                            DR_MEM <= {DR_MEM[15:8], regfile[DR_MEM[15:8]-8'hF0]};
                        else
                            DR_MEM <= {DR_MEM[15:8], mem_data_out};
                    end
                end
                IR: begin
                    if(v_sdr) DR_IR <= {tdi, DR_IR[15:1]};
                    else if(v_cdr) DR_IR <= {DR_IR[15:8], regfile[0]};
                end
            endcase
        end
    end

    //--------------------------------
    // UPDATE
    //--------------------------------
    always_ff @(posedge v_udr or negedge aclr) begin
        if(!aclr) begin
            for(i=0;i<16;i++) regfile[i] <= 0;
        end else begin
            // MEM write -> MMIO
            if(instr==MEM && DR_MEM[15:8] >= 8'hF0)
                regfile[DR_MEM[15:8]-8'hF0] <= DR_MEM[7:0];
            
            // IR write
            if(instr==IR)
                case(DR_IR[11:8])
                    8'hF9: regfile[9] <= DR_IR[7:0]; // step ctrl
                    8'hFA: regfile[10] <= DR_IR[7:0]; // counter
                    8'hF7: regfile[7] <= DR_IR[7:0]; // busy/done
                    default:
                        if(DR_IR[11:8] < 8'h10)
                            regfile[DR_IR[11:8]] <= DR_IR[7:0];
                endcase
        end
    end

    //--------------------------------
    // INSTANTIACIÓN DE MÓDULOS INTERNOS
    //--------------------------------
    start_pulse_detector u_start(
        .clk(tck),
        .aclr(aclr),
        .start_bit(regfile[6][0]),
        .start_pulse(start_proc_pulse)
    );

    step_unit u_step(
        .clk(tck),
        .aclr(aclr),
        .reg_f9(regfile[9]),
        .step_mode(step_mode),
        .step_pulse(step_pulse)
    );

    status_unit u_status(
        .clk(tck),
        .aclr(aclr),
        .reg_f7(regfile[7]),
        .busy(busy),
        .done(done)
    );

    //--------------------------------
    // NUEVAS ASIGNACIONES DE SALIDA (Mapeo a registros F0-FF)
    //--------------------------------
    // Asumiendo mapa: F0(L)-F1(H) Width, F2(L)-F3(H) Height, F4(L)-F5(H) Scale, F6 Mode
    assign cfg_width  = {regfile[1], regfile[0]}; 
    assign cfg_height = {regfile[3], regfile[2]};
    assign cfg_scale  = {regfile[5], regfile[4]};
    assign cfg_mode   = regfile[6];

endmodule
