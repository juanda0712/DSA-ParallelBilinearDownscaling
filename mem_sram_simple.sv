module mem_sram_simple #(
    parameter ADDR_BITS = 16,  // <--- 64KB (2^16)
    parameter DATA_BITS = 8
)(
    input  logic clk,
    input  logic we,
    input  logic [ADDR_BITS-1:0] addr,
    input  logic [DATA_BITS-1:0] data_in,
    output logic [DATA_BITS-1:0] data_out
);
    // Infiere BRAM
    logic [DATA_BITS-1:0] mem [0:(1<<ADDR_BITS)-1];

    always_ff @(posedge clk) begin
        if (we) mem[addr] <= data_in;
        data_out <= mem[addr];
    end
endmodule