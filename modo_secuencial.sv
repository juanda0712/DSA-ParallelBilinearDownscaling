// modo_secuencial.sv
`timescale 1ns/1ps
import formato_pkg::*;

module modo_secuencial
(
  input  logic clk,
  input  logic rst_n,

  // Control
  input  logic iniciar,              // pulso: cargar un nuevo conjunto
  output logic ocupado,              // 1 mientras se procesa este píxel
  output logic listo,                // 1 cuando puede llegar un nuevo iniciar

  // Entradas de un solo píxel
  input  logic [7:0] p00_entrada,
  input  logic [7:0] p10_entrada,
  input  logic [7:0] p01_entrada,
  input  logic [7:0] p11_entrada,
  input  q8_8_t      fx_entrada,
  input  q8_8_t      fy_entrada,

  // Salidas
  output logic [7:0] pixel_salida,
  output q8_8_t      pixel_salida_q
);

  // Registros de entrada (simulan acceso/manejo de memoria)
  logic [7:0] p00_r, p10_r, p01_r, p11_r;
  q8_8_t      fx_r, fy_r;

  logic valido_entrada;
  logic [7:0] pixel_salida_c;
  q8_8_t      pixel_salida_q_c;

  // Captura de entradas cuando iniciar=1
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      p00_r <= '0;
      p10_r <= '0;
      p01_r <= '0;
      p11_r <= '0;
      fx_r  <= '0;
      fy_r  <= '0;
      valido_entrada <= 1'b0;
    end
    else begin
      if (iniciar) begin
        p00_r <= p00_entrada;
        p10_r <= p10_entrada;
        p01_r <= p01_entrada;
        p11_r <= p11_entrada;
        fx_r  <= fx_entrada;
        fy_r  <= fy_entrada;
        valido_entrada <= 1'b1;
      end
      else begin
        valido_entrada <= 1'b0;
      end
    end
  end

  // Interpolador (el que ya tienes)
  interpolacion u_interpolacion (
    .p00(p00_r),
    .p10(p10_r),
    .p01(p01_r),
    .p11(p11_r),
    .fx (fx_r),
    .fy (fy_r),
    .pixel_out  (pixel_salida_c),
    .pixel_out_q(pixel_salida_q_c)
  );

  // Registro de salida
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pixel_salida    <= '0;
      pixel_salida_q <= '0;
    end
    else if (valido_entrada) begin
      pixel_salida    <= pixel_salida_c;
      pixel_salida_q <= pixel_salida_q_c;
    end
  end

  assign ocupado = valido_entrada;
  assign listo   = ~ocupado;

endmodule
