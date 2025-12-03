// registros_simd.sv
`timescale 1ns/1ps
import formato_pkg::*;

module registros_simd #(
  parameter int N = 4  // número de "lanes" SIMD
)(
  input  logic clk,
  input  logic rst_n,
  input  logic cargar,         // captura entradas cuando cargar=1

  // Entradas
  input  logic [7:0] p00_entrada [N],
  input  logic [7:0] p10_entrada [N],
  input  logic [7:0] p01_entrada [N],
  input  logic [7:0] p11_entrada [N],
  input  q8_8_t      fx_entrada  [N],
  input  q8_8_t      fy_entrada  [N],

  // Salidas registradas
  output logic [7:0] p00 [N],
  output logic [7:0] p10 [N],
  output logic [7:0] p01 [N],
  output logic [7:0] p11 [N],
  output q8_8_t      fx  [N],
  output q8_8_t      fy  [N]
);

  integer k;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (k = 0; k < N; k++) begin
        p00[k] <= '0;
        p10[k] <= '0;
        p01[k] <= '0;
        p11[k] <= '0;
        fx[k]  <= '0;
        fy[k]  <= '0;
      end
    end
    else if (cargar) begin
      for (k = 0; k < N; k++) begin
        p00[k] <= p00_entrada[k];
        p10[k] <= p10_entrada[k];
        p01[k] <= p01_entrada[k];
        p11[k] <= p11_entrada[k];
        fx[k]  <= fx_entrada[k];
        fy[k]  <= fy_entrada[k];
      end
    end
  end

endmodule
