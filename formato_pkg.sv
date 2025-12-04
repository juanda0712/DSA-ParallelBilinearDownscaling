// formato_pkg.sv
package formato_pkg;

  // Formato Q8.8 (16 bits: 8 enteros, 8 fraccionales)
  typedef logic signed [15:0] q8_8_t;

  // Convertir un píxel de 8 bits (0–255) a Q8.8
  function automatic q8_8_t to_q8_8(input logic [7:0] pix);
    to_q8_8 = {pix, 8'b0};   // << 8
  endfunction

  // Multiplicación Q8.8 x Q8.8 -> Q8.8
  function automatic q8_8_t q8_8_mul(input q8_8_t a, input q8_8_t b);
    logic signed [31:0] prod;
    prod     = a * b;      // Q16.16
    q8_8_mul = prod >>> 8; // bajar a Q8.8
  endfunction

  // Conversión Q8.8 -> píxel 8 bits, con redondeo y saturación [0,255]
  function automatic logic [7:0] from_q8_8_sat(input q8_8_t x);
    logic signed [15:0] tmp;
    // Redondear: sumar 0.5 (0x0080) antes de truncar
    tmp = x + 16'sh0080;

    if (tmp < 0)
      from_q8_8_sat = 8'd0;
    else if (tmp[15:8] > 8'd255)
      from_q8_8_sat = 8'd255;
    else
      from_q8_8_sat = tmp[15:8];  // tomar parte entera
  endfunction

  // Interpolación lineal 1D: lerp(a,b,t) = a + t*(b-a)
  function automatic q8_8_t lerp(
    input q8_8_t a,
    input q8_8_t b,
    input q8_8_t t
  );
    q8_8_t diff;
    diff = b - a;
    lerp = a + q8_8_mul(diff, t);
  endfunction

endpackage
