`timescale 1ns/1ps
import formato_pkg::*;

module modo_simd #(
  parameter int LANES = 4
)(
  input  logic clk,
  input  logic rst_n,

  // Control
  input  logic iniciar,      // Pulso de 1 ciclo desde la CU
  input  logic modo_paso,    // Para debug (Stepping)
  input  logic paso,         // Pulso de avance en Stepping
  
  output logic ocupado,      // No lo usaremos realmente, pero lo mantenemos por compatibilidad
  output logic listo,        // Pulso de "Terminé"

  // Entradas
  input  logic [7:0] p00_entrada [LANES],
  input  logic [7:0] p10_entrada [LANES],
  input  logic [7:0] p01_entrada [LANES],
  input  logic [7:0] p11_entrada [LANES],
  input  q8_8_t      fx_entrada  [LANES],
  input  q8_8_t      fy_entrada  [LANES],

  // Salidas
  output logic [7:0] pixel_salida   [LANES],
  output q8_8_t      pixel_salida_q [LANES]
);

  // -----------------------------------------------------------
  // 1. GESTIÓN DE RELOJ (SOPORTE PARA STEPPING)
  // -----------------------------------------------------------
  // Si modo_paso está activo, congelamos todo a menos que haya un pulso 'paso'.
  // Si modo_paso está inactivo (0), el sistema corre libre (enable = 1).
  logic clock_enable;
  assign clock_enable = (!modo_paso) || (modo_paso && paso);


  // -----------------------------------------------------------
  // 2. REGISTROS DE DATOS (PIPELINE DE 2 ETAPAS)
  // -----------------------------------------------------------
  // Etapa 1: Registros de Entrada
  logic [7:0] r_p00[LANES], r_p10[LANES], r_p01[LANES], r_p11[LANES];
  q8_8_t      r_fx[LANES],  r_fy[LANES];
  
  // Etapa 2: Cables de resultado combinacional
  logic [7:0] w_pixel_res[LANES];
  q8_8_t      w_pixel_q[LANES];

  integer k;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for(k=0; k<LANES; k++) begin
            r_p00[k] <= 0; r_p10[k] <= 0; r_p01[k] <= 0; r_p11[k] <= 0;
            r_fx[k]  <= 0; r_fy[k]  <= 0;
            pixel_salida[k] <= 0;
            pixel_salida_q[k] <= 0;
        end
    end else if (clock_enable) begin
        // Si nos dicen iniciar, capturamos la entrada (ETAPA 1)
        if (iniciar) begin
            for(k=0; k<LANES; k++) begin
                r_p00[k] <= p00_entrada[k];
                r_p10[k] <= p10_entrada[k];
                r_p01[k] <= p01_entrada[k];
                r_p11[k] <= p11_entrada[k];
                r_fx[k]  <= fx_entrada[k];
                r_fy[k]  <= fy_entrada[k];
            end
        end
        
        // Siempre actualizamos la salida con el resultado del cálculo (ETAPA 2)
        // Esto crea el efecto de "Latch" al final.
        // Solo guardamos si el control nos dice que hay dato válido (ver abajo)
        if (pipe_control[0]) begin
             for(k=0; k<LANES; k++) begin
                pixel_salida[k]   <= w_pixel_res[k];
                pixel_salida_q[k] <= w_pixel_q[k];
             end
        end
    end
  end

  // -----------------------------------------------------------
  // 3. DATAPATH (CÁLCULO PURO)
  // -----------------------------------------------------------
  genvar i;
  generate
    for (i = 0; i < LANES; i++) begin : GEN_LANES
      interpolacion u_interpolacion (
        .p00(r_p00[i]),
        .p10(r_p10[i]),
        .p01(r_p01[i]),
        .p11(r_p11[i]),
        .fx (r_fx[i]),
        .fy (r_fy[i]),
        .pixel_out  (w_pixel_res[i]),
        .pixel_out_q(w_pixel_q[i])
      );
    end
  endgenerate

  // -----------------------------------------------------------
  // 4. CONTROL DE PIPELINE (SHIFT REGISTER) - EL CORAZÓN DEL DISEÑO
  // -----------------------------------------------------------
  // En lugar de una FSM, usamos un registro de desplazamiento.
  // bit 0: "Estoy calculando" (Ciclo 1)
  // bit 1: "Terminé" (Ciclo 2)
  logic [1:0] pipe_control;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_control <= 2'b00;
    end else if (clock_enable) begin
        // Desplazamos el '1' de iniciar a través de la tubería
        // Iniciar -> pipe[0] -> pipe[1] (Listo)
        pipe_control <= {pipe_control[0], iniciar}; 
    end
  end

  // Señales de salida
  // Estamos ocupados si hay algún '1' viajando por la tubería
  assign ocupado = (pipe_control != 0); 
  
  // Estamos listos justo cuando el '1' llega al final (pipe[1] se enciende)
  // Esto genera un pulso PERFECTO de 1 ciclo.
  assign listo   = pipe_control[1];

endmodule