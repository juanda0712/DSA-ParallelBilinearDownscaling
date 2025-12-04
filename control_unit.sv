// control_unit.sv - CORREGIDO (LATENCIA RAM)
`timescale 1ns/1ps
import formato_pkg::*;

module control_unit (
    input  logic        clk,
    input  logic        aclr_n,
    
    // Control
    input  logic        start_proc_pulse,
    input  logic        step_mode,
    input  logic        step_pulse,
    
    // Configuración
    input  logic [15:0] cfg_width,
    input  logic [15:0] cfg_height,
    input  logic [15:0] cfg_scale, 
    input  logic [7:0]  cfg_mode,
    
    // Estado
    output logic        busy,
    output logic        done,
    
    // Memoria
    output logic        mem_we,
    output logic [15:0] mem_addr,     
    output logic [7:0]  mem_data_out,
    input  logic [7:0]  mem_data_in
);

    typedef enum logic [3:0] {
        IDLE, INIT, CALC_ADDR,
        REQ_P00,    // Solicitar P00
        REQ_P10,    // Solicitar P10 (P00 en transito)
        REQ_P01,    // Solicitar P01 (Llega P00)
        REQ_P11,    // Solicitar P11 (Llega P10)
        WAIT_P01,   // Esperar (Llega P01)
        COMPUTE,    // Calcular (Llega P11)
        WRITE_RES,  // Escribir
        NEXT_PIXEL, DONE_STATE
    } state_t;

    state_t state;
    logic start_sync, start_sync_d;
    logic [15:0] dst_x, dst_y;
    logic [31:0] src_acc_x, src_acc_y; 
    logic [15:0] src_x_int, src_y_int;
    q8_8_t       fx, fy;

    logic [7:0] p00_reg, p10_reg, p01_reg, p11_reg;
    logic [7:0] pixel_result;
    q8_8_t      pixel_result_q;
    logic [31:0] step_val;

    // Calculo del paso (1.0 / scale). 
    // Si Scale=0.5 (0x80), Paso=2.0. Si Scale=1.0, Paso=1.0.
    assign step_val = (cfg_scale == 16'h0080) ? 32'h00020000 : 32'h00010000;

    interpolacion u_core (
        .p00(p00_reg), .p10(p10_reg), .p01(p01_reg), .p11(p11_reg),
        .fx(fx), .fy(fy),
        .pixel_out(pixel_result), .pixel_out_q(pixel_result_q)
    );

    always_ff @(posedge clk or negedge aclr_n) begin
        if (!aclr_n) begin
            start_sync_d <= 0; start_sync <= 0;
        end else begin
            start_sync_d <= start_proc_pulse;
            start_sync   <= start_sync_d;
        end
    end

    always_ff @(posedge clk or negedge aclr_n) begin
        if (!aclr_n) begin
            state <= IDLE; busy <= 0; done <= 0;
            dst_x <= 0; dst_y <= 0; src_acc_x <= 0; src_acc_y <= 0;
            mem_we <= 0; mem_addr <= 0; mem_data_out <= 0;
            p00_reg <= 0; p10_reg <= 0; p01_reg <= 0; p11_reg <= 0;
        end else begin
            if (!step_mode || (step_mode && step_pulse)) begin
                case (state)
                    IDLE: begin
                        done <= 0;
                        if (start_sync) begin state <= INIT; busy <= 1; end 
                        else busy <= 0;
                    end

                    INIT: begin
                        dst_x <= 0; dst_y <= 0; src_acc_x <= 0; src_acc_y <= 0;
                        state <= CALC_ADDR;
                    end

                    CALC_ADDR: begin
                        src_x_int = src_acc_x[31:16];
                        src_y_int = src_acc_y[31:16];
                        fx = {8'b0, src_acc_x[15:8]}; 
                        fy = {8'b0, src_acc_y[15:8]};
                        if (src_x_int >= cfg_width - 1) src_x_int = cfg_width - 2;
                        if (src_y_int >= cfg_height - 1) src_y_int = cfg_height - 2;
                        state <= REQ_P00;
                    end

                    // PIPELINE DE LECTURA (AJUSTADO)
                    REQ_P00: begin
                        mem_we <= 0;
                        mem_addr <= (src_y_int * cfg_width) + src_x_int; // Pide P00
                        state <= REQ_P10;
                    end

                    REQ_P10: begin
                        mem_addr <= (src_y_int * cfg_width) + src_x_int + 1; // Pide P10
                        // P00 aun no llega, llega al final de este ciclo
                        state <= REQ_P01;
                    end

                    REQ_P01: begin
                        mem_addr <= ((src_y_int + 1) * cfg_width) + src_x_int; // Pide P01
                        p00_reg  <= mem_data_in; // <--- AQUI llega P00
                        state <= REQ_P11;
                    end

                    REQ_P11: begin
                        mem_addr <= ((src_y_int + 1) * cfg_width) + src_x_int + 1; // Pide P11
                        p10_reg  <= mem_data_in; // <--- AQUI llega P10
                        state <= WAIT_P01;
                    end
                    
                    WAIT_P01: begin
                        // No pedimos nada nuevo
                        p01_reg <= mem_data_in; // <--- AQUI llega P01
                        state <= COMPUTE;
                    end

                    COMPUTE: begin
                        p11_reg <= mem_data_in; // <--- AQUI llega P11
                        // Ahora tenemos los 4 vecinos, interpolacion es combinacional
                        state <= WRITE_RES;
                    end

                    WRITE_RES: begin
                        // Offset salida 0x4000
                        mem_addr <= 16'h4000 + (dst_y * cfg_width) + dst_x; 
                        mem_data_out <= pixel_result;
                        mem_we <= 1;
                        state <= NEXT_PIXEL;
                    end

                    NEXT_PIXEL: begin
                        mem_we <= 0;
                        // Logica para avanzar X, Y (simplificada para prueba)
                        // Si escala es 0.5, la imagen salida es W/2, H/2
                        if (dst_x < (cfg_width/2) - 1) begin
                             dst_x <= dst_x + 1;
                             src_acc_x <= src_acc_x + step_val;
                             state <= CALC_ADDR;
                        end else begin
                            dst_x <= 0;
                            src_acc_x <= 0;
                            if (dst_y < (cfg_height/2) - 1) begin
                                dst_y <= dst_y + 1;
                                src_acc_y <= src_acc_y + step_val;
                                state <= CALC_ADDR;
                            end else begin
                                state <= DONE_STATE;
                            end
                        end
                    end

                    DONE_STATE: begin
                        busy <= 0; done <= 1;
                        if (!start_sync) state <= IDLE;
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule