// modo_simd.sv
`timescale 1ns/1ps
import formato_pkg::*;

module modo_simd #(
  parameter int LANES = 4   // N píxeles/ciclo
)(
  input  logic clk,
  input  logic rst_n,

  // Control
  input  logic iniciar,      // pulso para iniciar un lote de N píxeles
  input  logic modo_paso,    // 0 = libre, 1 = stepping
  input  logic paso,         // pulso de paso en modo debug
  output logic ocupado,
  output logic listo,

  // Entradas: N conjuntos de vecinos + fracciones
  input  logic [7:0] p00_entrada [LANES],
  input  logic [7:0] p10_entrada [LANES],
  input  logic [7:0] p01_entrada [LANES],
  input  logic [7:0] p11_entrada [LANES],
  input  q8_8_t      fx_entrada  [LANES],
  input  q8_8_t      fy_entrada  [LANES],

  // Salidas: N píxeles interpolados
  output logic [7:0] pixel_salida   [LANES],
  output q8_8_t      pixel_salida_q [LANES]
);

  // Señales de la máquina de estados
  logic cargar, calcular, listo_oper;

  // Registros SIMD de entrada
  logic [7:0] p00 [LANES];
  logic [7:0] p10 [LANES];
  logic [7:0] p01 [LANES];
  logic [7:0] p11 [LANES];
  q8_8_t      fx  [LANES];
  q8_8_t      fy  [LANES];

  registros_simd #(.N(LANES)) u_registros (
    .clk          (clk),
    .rst_n        (rst_n),
    .cargar       (cargar),
    .p00_entrada  (p00_entrada),
    .p10_entrada  (p10_entrada),
    .p01_entrada  (p01_entrada),
    .p11_entrada  (p11_entrada),
    .fx_entrada   (fx_entrada),
    .fy_entrada   (fy_entrada),
    .p00          (p00),
    .p10          (p10),
    .p01          (p01),
    .p11          (p11),
    .fx           (fx),
    .fy           (fy)
  );

  // Interpoladores en paralelo
  logic [7:0] pixel_salida_c   [LANES];
  q8_8_t      pixel_salida_q_c [LANES];

  genvar i;
  generate
    for (i = 0; i < LANES; i++) begin : GEN_LANES
      interpolacion u_interpolacion (
        .p00(p00[i]),
        .p10(p10[i]),
        .p01(p01[i]),
        .p11(p11[i]),
        .fx (fx[i]),
        .fy (fy[i]),
        .pixel_out  (pixel_salida_c[i]),
        .pixel_out_q(pixel_salida_q_c[i])
      );
    end
  endgenerate

  // Registro de salidas cuando calcular=1
  integer k;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (k = 0; k < LANES; k++) begin
        pixel_salida[k]    <= '0;
        pixel_salida_q[k] <= '0;
      end
    end
    else if (calcular) begin
      for (k = 0; k < LANES; k++) begin
        pixel_salida[k]    <= pixel_salida_c[k];
        pixel_salida_q[k] <= pixel_salida_q_c[k];
      end
    end
  end

  // Máquina de estados de control
  maquina_de_estados u_maquina (
    .clk       (clk),
    .rst_n     (rst_n),
    .iniciar   (iniciar),
    .modo_paso (modo_paso),
    .paso      (paso),
    .cargar    (cargar),
    .calcular  (calcular),
    .listo_oper(listo_oper),
    .ocupado   (ocupado),
    .listo     (listo)
  );

endmodule