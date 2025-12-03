module mem_sram_simple #(
    parameter ADDR_BITS = 8,   // 256 bytes
    parameter DATA_BITS = 8
)(
    input  logic                 clk,
    input  logic                 we,
    input  logic [ADDR_BITS-1:0] addr,
    input  logic [DATA_BITS-1:0] data_in,
    output logic [DATA_BITS-1:0] data_out
);

    logic [DATA_BITS-1:0] mem [0:(1<<ADDR_BITS)-1];

    always_ff @(posedge clk) begin
        if (we)
            mem[addr] <= data_in;

        data_out <= mem[addr];
    end

endmodule
