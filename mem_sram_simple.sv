module mem_sram_simple #(
    parameter ADDR_BITS = 19,
    parameter MEM_DEPTH = 380000 
)(
    input  logic                 clk,
    input  logic                 we,
    input  logic [ADDR_BITS-1:0] addr,
    input  logic [7:0]           data_in,
    output logic [7:0]           data_out
);

    // DIRECTIVA IMPORTANTE: Forzar uso de bloques M10K
    // "no_rw_check" ayuda a evitar lógica extra de control de colisiones
    (* ramstyle = "no_rw_check, M10K" *) logic [7:0] mem [0:MEM_DEPTH-1];

    logic [ADDR_BITS-1:0] addr_reg;

    always_ff @(posedge clk) begin
        if (we) begin
            // La protección de ESCRITURA sí se suele permitir sin romper la inferencia
            if (addr < MEM_DEPTH) begin
                mem[addr] <= data_in;
            end
        end
        
        // LECTURA LIMPIA: Sin IF/ELSE en la salida de datos.
        // Quartus necesita ver esto limpio para usar el bloque de hardware.
        data_out <= mem[addr];
    end

endmodule