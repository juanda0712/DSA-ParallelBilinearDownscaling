// control_unit.sv - VERSIÓN FINAL ROBUSTA
// Corrige bug de direccionamiento SIMD y Timeout
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
    input  logic [7:0]  cfg_mode,   // 0=Sec, 1=SIMD
    
    // Estado
    output logic        busy,
    output logic        done,
    
    // Memoria
    output logic        mem_we,
    output logic [15:0] mem_addr,     
    output logic [7:0]  mem_data_out,
    input  logic [7:0]  mem_data_in
);

    // Estados
    typedef enum logic [4:0] {
        IDLE, INIT, CALC_ADDR,
        // Secuencial
        REQ_P00, REQ_P10, REQ_P01, REQ_P11, WAIT_P01, COMPUTE_SEQ, WRITE_SEQ,
        // SIMD
        SIMD_FETCH_INIT, SIMD_FETCH_REQ, SIMD_FETCH_WAIT, SIMD_STORE_VEC,
        COMPUTE_SIMD, WAIT_SIMD, WRITE_SIMD_LOOP,
        // Común
        NEXT_PIXEL, DONE_STATE
    } state_t;

    state_t state;
    logic start_sync, start_sync_d;
    
    // Contadores de Destino
    logic [15:0] dst_x, dst_y;
    
    // Acumuladores de Coordenada Fuente (Q16.16)
    logic [31:0] src_acc_x, src_acc_y; 
    
    // Coordenada Fuente Temporal (para cálculos SIMD iterativos)
    logic [31:0] temp_src_acc_x; 

    // Coordenadas enteras/frac
    logic [15:0] src_x_int, src_y_int;
    q8_8_t       fx, fy;
    logic [31:0] step_val;

    // --- SECUENCIAL ---
    logic [7:0] p00_reg, p10_reg, p01_reg, p11_reg;
    logic [7:0] pix_res_seq;

    // --- SIMD (N=4) ---
    localparam LANES = 4;
    logic [7:0] p00_vec[LANES], p10_vec[LANES], p01_vec[LANES], p11_vec[LANES];
    q8_8_t      fx_vec[LANES],  fy_vec[LANES];
    logic [7:0] pix_res_vec[LANES];
    q8_8_t      pix_res_q_vec[LANES];
    
    logic       simd_start, simd_busy, simd_ready;
    logic [2:0] lane_idx; // 0..3
    logic [2:0] fetch_step; 

    // Paso: 1.0 / Scale. (0.5 -> 2.0)
    assign step_val = (cfg_scale == 16'h0080) ? 32'h00020000 : 32'h00010000;

    // Instancias
    interpolacion u_core_seq (
        .p00(p00_reg), .p10(p10_reg), .p01(p01_reg), .p11(p11_reg),
        .fx(fx), .fy(fy), .pixel_out(pix_res_seq), .pixel_out_q()
    );

    modo_simd #(.LANES(LANES)) u_core_simd (
        .clk(clk), .rst_n(aclr_n),
        .iniciar(simd_start), .modo_paso(1'b0), .paso(1'b0),
        .ocupado(simd_busy), .listo(simd_ready),
        .p00_entrada(p00_vec), .p10_entrada(p10_vec),
        .p01_entrada(p01_vec), .p11_entrada(p11_vec),
        .fx_entrada(fx_vec),   .fy_entrada(fy_vec),
        .pixel_salida(pix_res_vec), .pixel_salida_q(pix_res_q_vec)
    );

    always_ff @(posedge clk or negedge aclr_n) begin
        if (!aclr_n) begin
            start_sync_d <= 0; start_sync <= 0;
        end else begin
            start_sync_d <= start_proc_pulse;
            start_sync   <= start_sync_d;
        end
    end

    // FSM Principal
    always_ff @(posedge clk or negedge aclr_n) begin
        if (!aclr_n) begin
            state <= IDLE; busy <= 0; done <= 0;
            dst_x <= 0; dst_y <= 0; src_acc_x <= 0; src_acc_y <= 0;
            mem_we <= 0; mem_addr <= 0; mem_data_out <= 0;
            simd_start <= 0; lane_idx <= 0; fetch_step <= 0;
            temp_src_acc_x <= 0;
        end else begin
            if (!step_mode || (step_mode && step_pulse)) begin
                case (state)
                    IDLE: begin
                        done <= 0; simd_start <= 0;
                        if (start_sync) begin state <= INIT; busy <= 1; end 
                        else busy <= 0;
                    end

                    INIT: begin
                        dst_x <= 0; dst_y <= 0; src_acc_x <= 0; src_acc_y <= 0;
                        state <= CALC_ADDR;
                    end

                    CALC_ADDR: begin
                        // Preparar variables comunes
                        src_y_int = src_acc_y[31:16];
                        if (src_y_int >= cfg_height - 1) src_y_int = cfg_height - 2;

                        if (cfg_mode == 0) begin
                            // MODO SECUENCIAL
                            temp_src_acc_x = src_acc_x; // Usar el acumulador global
                            src_x_int = temp_src_acc_x[31:16];
                            fx = {8'b0, temp_src_acc_x[15:8]};
                            if (src_x_int >= cfg_width - 1) src_x_int = cfg_width - 2;
                            fy = {8'b0, src_acc_y[15:8]};
                            
                            state <= REQ_P00;
                        end else begin
                            // MODO SIMD
                            lane_idx <= 0;
                            temp_src_acc_x <= src_acc_x; // Copia local para iterar lanes
                            state <= SIMD_FETCH_INIT;
                        end
                    end

                    // --- SECUENCIAL ---
                    REQ_P00: begin mem_we<=0; mem_addr <= (src_y_int*cfg_width)+src_x_int; state <= REQ_P10; end
                    REQ_P10: begin mem_addr <= (src_y_int*cfg_width)+src_x_int+1; state <= REQ_P01; end
                    REQ_P01: begin mem_addr <= ((src_y_int+1)*cfg_width)+src_x_int; p00_reg<=mem_data_in; state <= REQ_P11; end
                    REQ_P11: begin mem_addr <= ((src_y_int+1)*cfg_width)+src_x_int+1; p10_reg<=mem_data_in; state <= WAIT_P01; end
                    WAIT_P01: begin p01_reg <= mem_data_in; state <= COMPUTE_SEQ; end
                    COMPUTE_SEQ: begin p11_reg <= mem_data_in; state <= WRITE_SEQ; end
                    WRITE_SEQ: begin
                        mem_addr <= 16'h4000 + (dst_y * cfg_width) + dst_x; // Offset salida
                        mem_data_out <= pix_res_seq;
                        mem_we <= 1;
                        state <= NEXT_PIXEL;
                    end

                    // --- SIMD FETCH ---
                    // Iteramos 4 veces para llenar los vectores
                    SIMD_FETCH_INIT: begin
                        // Calcular coords para el lane actual usando la copia temporal
                        src_x_int = temp_src_acc_x[31:16];
                        fx = {8'b0, temp_src_acc_x[15:8]};
                        if (src_x_int >= cfg_width - 1) src_x_int = cfg_width - 2;
                        
                        // Guardar Fracciones
                        fx_vec[lane_idx] <= fx;
                        fy_vec[lane_idx] <= {8'b0, src_acc_y[15:8]};
                        
                        fetch_step <= 0;
                        state <= SIMD_FETCH_REQ;
                    end

                    SIMD_FETCH_REQ: begin
                        // Máquina de lectura de 4 vecinos (Similar a secuencial pero guardando en vectores)
                        mem_we <= 0;
                        case(fetch_step)
                            0: begin mem_addr<=(src_y_int*cfg_width)+src_x_int; fetch_step<=1; end 
                            1: begin mem_addr<=(src_y_int*cfg_width)+src_x_int+1; fetch_step<=2; end
                            2: begin mem_addr<=((src_y_int+1)*cfg_width)+src_x_int; p00_vec[lane_idx]<=mem_data_in; fetch_step<=3; end
                            3: begin mem_addr<=((src_y_int+1)*cfg_width)+src_x_int+1; p10_vec[lane_idx]<=mem_data_in; fetch_step<=4; end
                            4: begin p01_vec[lane_idx]<=mem_data_in; fetch_step<=5; end
                            5: begin 
                                p11_vec[lane_idx]<=mem_data_in; 
                                state <= SIMD_FETCH_WAIT; // Fin de este lane
                            end
                        endcase
                    end

                    SIMD_FETCH_WAIT: begin
                        // Preparar siguiente lane
                        if (lane_idx == LANES-1) begin
                            state <= COMPUTE_SIMD;
                        end else begin
                            lane_idx <= lane_idx + 1;
                            temp_src_acc_x <= temp_src_acc_x + step_val; // Avanzar coord temporal
                            state <= SIMD_FETCH_INIT;
                        end
                    end

                    COMPUTE_SIMD: begin
                        simd_start <= 1;
                        state <= WAIT_SIMD;
                    end

                    WAIT_SIMD: begin
                        simd_start <= 0;
                        // Esperar a que el módulo diga que terminó (listo sube)
                        // Agregamos chequeo de !simd_start para asegurar que pasó un ciclo
                        if (simd_ready && !simd_start) begin
                             lane_idx <= 0;
                             state <= WRITE_SIMD_LOOP;
                        end
                    end

                    WRITE_SIMD_LOOP: begin
                        // Escribir 4 resultados
                        // dst_x NO se ha movido, así que dst_x + lane_idx es correcto
                        mem_addr <= 16'h4000 + (dst_y * cfg_width) + (dst_x + lane_idx);
                        mem_data_out <= pix_res_vec[lane_idx];
                        mem_we <= 1;
                        
                        if (lane_idx == LANES-1) begin
                            state <= NEXT_PIXEL;
                        end else begin
                            lane_idx <= lane_idx + 1;
                        end
                    end

                    NEXT_PIXEL: begin
                        mem_we <= 0;
                        
                        if (cfg_mode == 0) begin
                            // AVANCE SECUENCIAL (+1)
                            if (dst_x < (cfg_width/2) - 1) begin
                                 dst_x <= dst_x + 1;
                                 src_acc_x <= src_acc_x + step_val;
                                 state <= CALC_ADDR;
                            end else begin
                                goto_next_row();
                            end
                        end else begin
                            // AVANCE SIMD (+LANES)
                            // dst_x apunta al inicio del bloque actual.
                            // Próximo bloque está en dst_x + LANES
                            if ((dst_x + LANES) < (cfg_width/2)) begin 
                                dst_x <= dst_x + LANES;
                                // Avanzamos el acumulador global N pasos
                                src_acc_x <= src_acc_x + (step_val << 2); // step * 4
                                state <= CALC_ADDR;
                            end else begin
                                goto_next_row();
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

    task goto_next_row();
        dst_x <= 0;
        src_acc_x <= 0;
        if (dst_y < (cfg_height/2) - 1) begin
            dst_y <= dst_y + 1;
            src_acc_y <= src_acc_y + step_val;
            state <= CALC_ADDR;
        end else begin
            state <= DONE_STATE;
        end
    endtask

endmodule