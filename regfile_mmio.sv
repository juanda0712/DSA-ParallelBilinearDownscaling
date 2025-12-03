// regfile_mmio.sv
module regfile_mmio (
    input  logic        aclr,
    input  logic        v_udr,          // used to latch writes
    input  logic [2:0]  current_instr,  // from top (ir_in)
    input  logic [15:0] DR_MEM,         // for MEM writes
    input  logic [15:0] DR_IR,          // for IR writes (for regfile writes)
    input  logic [7:0]  mmio_query_addr,// address for read (0xF0..0xFF)
    output logic [7:0]  mmio_query_data,// data returned for that read

    // alias outputs
    output logic [15:0] width,
    output logic [15:0] height,
    output logic [15:0] scale_q8_8,
    output logic [7:0]  mode_reg,
    output logic [7:0]  status_reg,
    output logic [15:0] image_in_base
);

    // regfile: 16 bytes mapped to 0xF0..0xFF
    logic [7:0] regfile [0:15];
    integer ii;

    // Initialize / reset
    always_ff @(posedge v_udr or negedge aclr) begin
        if (!aclr) begin
            for (ii = 0; ii < 16; ii = ii + 1)
                regfile[ii] <= 8'h00;
        end
        else begin
            // If MEM write to MMIO area (0xF0..0xFF) write into regfile
            if ((current_instr == 3'b011) && (DR_MEM[15:8] >= 8'hF0)) begin
                regfile[DR_MEM[15:8] - 8'hF0] <= DR_MEM[7:0];
            end
            // If IR write, and not special F9/F A (handled in step_unit),
            // allow writing into regfile via IR (addresses 0x00..0x0F mapping).
            else if (current_instr == 3'b001) begin
                // DR_IR[11:8] is the index used in your original design for regfile writes
                // Only write when DR_IR[11:8] is in 0x00..0x0F range
                if (DR_IR[11:8] <= 8'h0F) begin
                    regfile[DR_IR[11:8]] <= DR_IR[7:0];
                end
            end
        end
    end

    // Combinational readback for mmio_query_addr
    always_comb begin
        if (mmio_query_addr >= 8'hF0) begin
            mmio_query_data = regfile[mmio_query_addr - 8'hF0];
        end
        else begin
            mmio_query_data = 8'h00;
        end
    end

    // alias wiring
    assign width       = { regfile[8'hF1 - 8'hF0], regfile[8'hF0 - 8'hF0] }; // F1:F0
    assign height      = { regfile[8'hF3 - 8'hF0], regfile[8'hF2 - 8'hF0] }; // F3:F2
    assign scale_q8_8  = { regfile[8'hF5 - 8'hF0], regfile[8'hF4 - 8'hF0] }; // F5:F4
    assign mode_reg    = regfile[8'hF6 - 8'hF0];                            // F6
    assign status_reg  = regfile[8'hF7 - 8'hF0];                            // F7
    assign image_in_base = { regfile[8'hFF - 8'hF0], regfile[8'hFE - 8'hF0] }; // FF:FE

endmodule
