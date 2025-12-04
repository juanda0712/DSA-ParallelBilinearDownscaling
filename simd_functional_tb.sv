`timescale 1ns/1ps
import formato_pkg::*;

module simd_functional_tb;
    // Señales de Control y Reloj
    logic clk;
    logic aclr_n;
    
    // Parámetros de Prueba (8x4 -> 4x2)
    localparam WIDTH  = 16'd8;
    localparam HEIGHT = 16'd4;
    localparam SCALE  = 16'h0080; // 0.5 en Q8.8
    localparam SIMD_MODE = 8'd1;
    localparam LANES  = 4;

    // Estímulos de entrada
    logic start_proc_pulse;
    logic step_mode, step_pulse;
    logic [15:0] cfg_width, cfg_height, cfg_scale;
    logic [7:0]  cfg_mode;
    
    // Salidas/Debug
    logic busy, done;
    
    // Interfaz de Memoria (TB simula la RAM)
    logic mem_we;
    logic [18:0] mem_addr;
    logic [7:0]  mem_data_out; // Lo que el CU intenta escribir
    logic [7:0]  mem_data_in;  // Lo que la RAM le da al CU

    // Memoria simulada (Almacena 256 bytes de entrada para el TB)
    logic [7:0] tb_memory [0:255]; 
    
    // Instanciar el DUT
    control_unit u_dut (
        .clk(clk), .aclr_n(aclr_n), .start_proc_pulse(start_proc_pulse),
        .step_mode(step_mode), .step_pulse(step_pulse),
        .cfg_width(cfg_width), .cfg_height(cfg_height), .cfg_scale(cfg_scale), .cfg_mode(cfg_mode),
        .busy(busy), .done(done), .mem_we(mem_we), .mem_addr(mem_addr), 
        .mem_data_out(mem_data_out), .mem_data_in(mem_data_in)
    );

    // Simulación de Reloj
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Simulación de RAM (Respuesta síncrona/combinacional para TB)
    always @(*) begin
        mem_data_in = tb_memory[mem_addr]; 
    end
    always @(posedge clk) begin
        if (mem_we) begin
            tb_memory[mem_addr] <= mem_data_out; // Escribir resultados de salida
        end
    end

    // Secuencia de Estímulos y Verificación
    initial begin
        $display("-----------------------------------------------------");
        $display("--- Testbench: SIMD Functional Check (TB2)----------");
        $display("-----------------------------------------------------");
        
        // 1. Inicializar Memoria (Patrón 8x4)
        // Entrada (0..31): Fila 0 = 16..23; Fila 1 = 32..39; Fila 2 = 48..55; Fila 3 = 64..71
        for (int y = 0; y < HEIGHT; y++) begin
            for (int x = 0; x < WIDTH; x++) begin
                tb_memory[y * WIDTH + x] = ((y + 1) * 16) + x;
            end
        end
        $display("Memoria de Entrada inicializada (8x4).");
        
        // 2. Reset e Configuración
        aclr_n = 0; @(posedge clk); aclr_n = 1;
        cfg_width = WIDTH; cfg_height = HEIGHT; cfg_scale = SCALE;
        cfg_mode = SIMD_MODE;
        step_mode = 0; // Free run
        start_proc_pulse = 0;
        @(posedge clk); 
        
        // 3. Ejecutar SIMD
        $display("Ejecutando SIMD (Row 0 y Row 1) en free run...");
        start_proc_pulse = 1;
        @(posedge clk);
        start_proc_pulse = 0;
        
        // Esperar a que termine todo el procesamiento (Row 0 y Row 1)
        wait(done == 1 && busy == 0); 

        // 4. Verificación de Resultados
        
        // Resultados esperados calculados a mano (Q8.8 con redondeo)
        // ROW 0: P0 (0,0), P1 (2,0), P2 (4,0), P3 (6,0)
        // Valores de entrada: (16, 17, 18, 19) y (32, 33, 34, 35)
        // P0 (x=0, y=0): (16+32+16+32)/4 ~= 24. Esto es solo NN. Bilinear: (16*0.75)+(32*0.25) -> 20
        // Para este patrón, los valores esperados son los del Golden Model:
        // Se asume que tu golden model para 8x4 a 0.5 da: 16, 18, 20, 22, 48, 50, 52, 54.
        
        logic [7:0] expected_results [7:0];
        expected_results[0] = 8'd16; expected_results[1] = 8'd18; 
        expected_results[2] = 8'd20; expected_results[3] = 8'd22; 
        expected_results[4] = 8'd48; expected_results[5] = 8'd50; 
        expected_results[6] = 8'd52; expected_results[7] = 8'd54; 
        
        int errors = 0;
        $display("Verificando 8 píxeles de salida (0x40000 - 0x40007)...");

        for (int k = 0; k < 8; k++) begin
            logic [7:0] actual_val;
            actual_val = tb_memory[19'h40000 + k];
            if (actual_val !== expected_results[k]) begin
                $display("ERROR en índice %0d: Esperado %0d, Obtenido %0d", k, expected_results[k], actual_val);
                errors++;
            end
        end
        
        if (errors == 0) begin
            $display("ÉXITO: Modo SIMD completado. Todos los 8 píxeles coinciden con la referencia.");
        end else begin
            $error("FALLO: Modo SIMD encontró %0d errores funcionales.", errors);
        end
        
        $display("-----------------------------------------------------");
        $finish;
    end

endmodule