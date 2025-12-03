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

    // Interfaz Memoria (16 addr + 8 data)
    output logic        mem_we,
    output logic [15:0] mem_addr,
    output logic [7:0]  mem_data_in,
    input  logic [7:0]  mem_data_out,

    // Control hacia Datapath
    output logic        step_mode,
    output logic        step_pulse,
    output logic        start_proc_pulse,
    
    // CORRECCIÓN: Ahora son ENTRADAS (leemos el hardware)
    input  logic        hw_busy,  
    input  logic        hw_done,

    // Configuración outputs
    output logic [15:0] cfg_width,
    output logic [15:0] cfg_height,
    output logic [15:0] cfg_scale,
    output logic [7:0]  cfg_mode
);
    typedef enum logic [2:0] { 
        BYPASS    = 3'b000, 
        REG_OP    = 3'b001, 
        READ_MEM  = 3'b010, 
        WRITE_MEM = 3'b011  
    } jtag_instr_e;

    jtag_instr_e instr;
    assign instr = jtag_instr_e'(ir_in);

    logic [7:0] regfile [0:15];
    integer i;

    logic [2:0]  DR0;
    logic [23:0] DR_MEM; 
    logic [15:0] DR_IR;

    // Asignaciones Memoria
    assign mem_addr    = DR_MEM[23:8];
    assign mem_data_in = DR_MEM[7:0];
    assign mem_we      = (instr == WRITE_MEM && v_udr && DR_MEM[23:8] < 16'hFFF0); 

    // TDO Mux
    always_comb begin
        case(instr)
            BYPASS:    tdo = DR0[0];
            READ_MEM:  tdo = DR_MEM[0];
            WRITE_MEM: tdo = DR_MEM[0];
            REG_OP:    tdo = DR_IR[0];
            default:   tdo = 1'b0;
        endcase
    end

    // Shift / Capture
    always_ff @(posedge tck or negedge aclr) begin
        if(!aclr) begin
            DR0 <= 0; DR_MEM <= 0; DR_IR <= 0;
        end else begin
            case(instr)
                BYPASS: if(v_sdr) DR0 <= {tdi, DR0[2:1]};
                
                READ_MEM, WRITE_MEM: begin
                    if(v_sdr) DR_MEM <= {tdi, DR_MEM[23:1]};
                    else if(v_cdr) DR_MEM <= {DR_MEM[23:8], mem_data_out}; 
                end
                
                REG_OP: begin
                    if(v_sdr) DR_IR <= {tdi, DR_IR[15:1]};
                    else if(v_cdr) begin
                         // CORRECCIÓN CRITICA:
                         // Cuando la PC lee status, le enviamos las señales reales del HW.
                         // Bit 0: Busy, Bit 1: Done
                         DR_IR <= {DR_IR[15:8], {6'b0, hw_done, hw_busy}}; 
                    end
                end
            endcase
        end
    end

    // Update (Registros)
    always_ff @(posedge v_udr or negedge aclr) begin
        if(!aclr) begin
            for(i=0;i<16;i++) regfile[i] <= 0;
        end else begin
            if(instr == WRITE_MEM && DR_MEM[23:8] >= 16'hFFF0) begin
                 regfile[DR_MEM[23:8] - 16'hFFF0] <= DR_MEM[7:0];
            end
            if(instr == REG_OP) begin
                if(DR_IR[11:8] < 16) regfile[DR_IR[11:8]] <= DR_IR[7:0];
                
                case(DR_IR[11:8])
                    8'hF9: regfile[9] <= DR_IR[7:0];
                    8'hFA: regfile[10] <= DR_IR[7:0];
                    // Nota: Ya no escribimos F7 desde JTAG, es solo lectura HW
                endcase
            end
        end
    end

    // Instancias internas
    start_pulse_detector u_start(.clk(tck), .aclr(aclr), .start_bit(regfile[6][0]), .start_pulse(start_proc_pulse));
    step_unit u_step(.clk(tck), .aclr(aclr), .reg_f9(regfile[9]), .step_mode(step_mode), .step_pulse(step_pulse));

    // Salidas Config
    assign cfg_width  = {regfile[1], regfile[0]}; 
    assign cfg_height = {regfile[3], regfile[2]};
    assign cfg_scale  = {regfile[5], regfile[4]};
    assign cfg_mode   = regfile[6];

endmodule