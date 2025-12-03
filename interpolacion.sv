// interpolacion.sv
`timescale 1ns/1ps

import formato_pkg::*;

module interpolacion
(
  // Píxeles vecinos (8 bits, gris)
  input  logic [7:0] p00, // (x,   y)
  input  logic [7:0] p10, // (x+1, y)
  input  logic [7:0] p01, // (x,   y+1)
  input  logic [7:0] p11, // (x+1, y+1)

  // Coordenadas fraccionarias en Q8.8
  input  q8_8_t fx,        // fracción horizontal
  input  q8_8_t fy,        // fracción vertical

  // Resultado
  output logic [7:0] pixel_out,  // píxel interpolado (0–255)
  output q8_8_t      pixel_out_q // mismo valor en Q8.8 
);

  // Representación interna Q8.8 de los píxeles
  q8_8_t p00_q, p10_q, p01_q, p11_q;
  q8_8_t i0, i1;
  q8_8_t out_q;

  always_comb begin
    // Pasar de 8 bits a Q8.8
    p00_q = to_q8_8(p00);
    p10_q = to_q8_8(p10);
    p01_q = to_q8_8(p01);
    p11_q = to_q8_8(p11);

    // Interpolación horizontal 
    i0 = lerp(p00_q, p10_q, fx); // fila superior
    i1 = lerp(p01_q, p11_q, fx); // fila inferior

    // Interpolación vertical entre filas (usa fy)
    out_q = lerp(i0, i1, fy);

    pixel_out_q = out_q;
    pixel_out   = from_q8_8_sat(out_q);
  end

endmodule
