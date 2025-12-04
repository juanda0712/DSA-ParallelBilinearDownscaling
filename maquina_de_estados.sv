`timescale 1ns/1ps

module maquina_de_estados
(
  input  logic clk,
  input  logic rst_n,

  input  logic iniciar,      // pulso para comenzar una operación
  input  logic modo_paso,    // 0 = libre, 1 = avanzar solo cuando paso=1
  input  logic paso,         // pulso de "single step" en modo debug

  output logic cargar,       // ciclo de carga de registros de entrada
  output logic calcular,     // ciclo de cálculo / captura de salidas
  output logic listo_oper,   // pulso de operación completada

  output logic ocupado,      // 1 mientras la operación está en curso
  output logic listo         // 1 cuando se puede aceptar un nuevo iniciar
);

  typedef enum logic [1:0] {
    S_ESPERA,
    S_CARGA,
    S_CALCULO,
    S_LISTO
  } estado_t;

  estado_t estado, siguiente;

  logic avanzar;
  assign avanzar = (modo_paso) ? paso : 1'b1;

  // Registro de estado
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      estado <= S_ESPERA;
    else if (avanzar)
      estado <= siguiente;
  end

  // Lógica de transición y salidas
  always_comb begin
    siguiente   = estado;
    cargar      = 1'b0;
    calcular    = 1'b0;
    listo_oper  = 1'b0;

    case (estado)
      S_ESPERA: begin
        if (iniciar)
          siguiente = S_CARGA;
      end

      S_CARGA: begin
        cargar    = 1'b1;
        siguiente = S_CALCULO;
      end

      S_CALCULO: begin
        calcular  = 1'b1;
        siguiente = S_LISTO;
      end

      S_LISTO: begin
        listo_oper = 1'b1;
        if (iniciar)
          siguiente = S_CARGA; // encadenar otra operación
        else
          siguiente = S_ESPERA;
      end

      default: siguiente = S_ESPERA;
    endcase
  end

  assign ocupado = (estado == S_CARGA) || (estado == S_CALCULO);
  
  // ---------------------------------------------------------
  // CORRECCIÓN CRÍTICA AQUÍ ABAJO
  // ---------------------------------------------------------
  // Antes tenías: (estado == S_ESPERA) || (estado == S_LISTO)
  // Eso causaba que la CU leyera datos antes de tiempo.
  // Ahora forzamos a que la CU espere hasta que el cálculo termine REALMENTE.
  assign listo   = (estado == S_LISTO); 

endmodule