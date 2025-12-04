`timescale 1ns/1ps
import formato_pkg::*;

module control_unit_stepping_tb;
    // Señales de Control y Reloj
    logic clk;
    logic aclr_n;
    
    // Puertos del DUT (control_unit)
    logic start_proc_pulse;
    logic step_mode;
    logic step_pulse;
    logic [15:0] cfg_width, cfg_height, cfg_scale;
    logic [7:0]  cfg_mode;
    logic busy, done;
    
    // Interfaz de Memoria (TB simula la RAM)
    logic mem_we;
    logic [18:0] mem_addr;
    logic [7:0]  mem_data_out;
    logic [7:0]  mem_data_in;

    // Parámetros de Prueba (8x4 -> 4x2)
    localparam WIDTH  = 16'd8;
    localparam HEIGHT = 16'd4;
    localparam SCALE  = 16'h0080; // 0.5 en Q8.8
    localparam SECUENCIAL = 8'd0;
    
    // Señal de control para simulación
    logic tb_stop = 0;
    
    // Instanciar el DUT (Control Unit)
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
        forever #5 clk = ~clk; // 100 MHz clock (10 ns period)
    end

    // Simulación de Memoria SRAM (Respuesta inmediata para TB)
    logic [7:0] tb_memory [0:255]; // Solo 256 bytes para TB simple
    
    initial begin
        // Inicializar memoria de entrada para tener píxeles válidos (P00, P10, P01, P11)
        tb_memory[0] = 8'd10; tb_memory[1] = 8'd20; 
        tb_memory[WIDTH] = 8'd30; tb_memory[WIDTH+1] = 8'd40;
    end
    
    always @(posedge clk) begin
        if (mem_we) begin
            tb_memory[mem_addr] <= mem_data_out; // Escribir en RAM
        end
        // Lectura de memoria (1 ciclo de latencia - Asumimos mem_data_in es combinacional)
        mem_data_in = tb_memory[mem_addr]; 
    end


    // Secuencia de Estímulos y Verificación
    initial begin
        $display("-----------------------------------------------------");
        $display("--- Testbench: Stepping Control Verification (TB1)---");
        $display("-----------------------------------------------------");

        // 1. Reset
        aclr_n = 0;
        cfg_mode = SECUENCIAL;
        @(posedge clk); 
        aclr_n = 1;
        
        // 2. Configuración
        cfg_width = WIDTH;
        cfg_height = HEIGHT;
        cfg_scale = SCALE;
        step_mode = 1;      // Activar Stepping
        step_pulse = 0;
        start_proc_pulse = 0;
        @(posedge clk); 

        // 3. START: De IDLE a INIT, debe pausar en CALC_ADDR
        start_proc_pulse = 1;
        @(posedge clk);
        start_proc_pulse = 0;
        
        // Esperar la pausa después de INIT (debe estar en CALC_ADDR)
        // La FSM avanza IDLE -> INIT -> CALC_ADDR en dos ciclos (porque pulso=0)
        @(posedge clk); 
        @(posedge clk); 
        
        // VERIFICACION DE PAUSA
        if (u_dut.state != control_unit::CALC_ADDR) $error("FALLO Stepping: No se detuvo en CALC_ADDR. Estado: %s", u_dut.state.name());
        if (busy != 1) $error("FALLO Stepping: Busy no esta activo.");
        $display("PAUSA OK: HW detenido en CALC_ADDR. Busy=%b", busy);

        // 4. Avance por pasos (Single Step)
        $display("Iniciando avance por pasos:");
        
        // REQ_P00
        step_pulse = 1; @(posedge clk); step_pulse = 0;
        if (u_dut.state != control_unit::REQ_P00) $error("FALLO: Paso 1. Esperaba REQ_P00.");
        
        // WAIT_P00 (Lee memoria 0)
        step_pulse = 1; @(posedge clk); step_pulse = 0;
        if (u_dut.state != control_unit::WAIT_P00) $error("FALLO: Paso 2. Esperaba WAIT_P00.");
        
        // REQ_P10
        step_pulse = 1; @(posedge clk); step_pulse = 0;
        if (u_dut.state != control_unit::REQ_P10) $error("FALLO: Paso 3. Esperaba REQ_P10.");

        // ... (Se podrían continuar los 12+ pasos hasta WRITE_SEQ) ...
        
        $display("STEPPING OK: Avance verificado hasta REQ_P10.");

        // 5. Liberar ejecución (Correr libremente hasta terminar)
        step_mode = 0; // Desactivar stepping
        @(posedge clk);
        $display("Liberando el reloj (step_mode=0). Esperando done=1...");
        
        // Esperar a que el busy baje y done suba
        wait(done == 1 && busy == 0); 
        
        $display("-----------------------------------------------------");
        $display("TERMINADO. DONE=1. La simulación de Stepping es exitosa.");
        $display("-----------------------------------------------------");
        $finish;
    end
endmodule