// control_unit.sv (VERSIÓN FINAL CON CORRECCIÓN DE PROTOCOLO DE CONTADORES)
// Corrige bug de direccionamiento SIMD y Timeout
`timescale 1ns/1ps
import formato_pkg::*;
module control_unit (
    input  logic        clk,
    input  logic        aclr_n,
    
    // Control
    input  logic        start_proc_pulse, // NIVEL DESDE CONNECT
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
        // Secuencial con latencia de 1 ciclo
        REQ_P00, WAIT_P00, REQ_P10, WAIT_P10, REQ_P01, WAIT_P01_A, REQ_P11, WAIT_P11,
        COMPUTE_SEQ, WRITE_SEQ, 
        // SIMD
        SIMD_FETCH_INIT, SIMD_FETCH_REQ, SIMD_FETCH_WAIT, SIMD_STORE_VEC,
        COMPUTE_SIMD, WAIT_SIMD, WRITE_SIMD_LOOP,
        // Común
        NEXT_PIXEL, DONE_STATE, 
        // ESTADOS PARA ESCRITURA DE CONTADORES
        WRITE_FLOP_L, WRITE_FLOP_H, WRITE_READ_L, WRITE_READ_H, WRITE_WRITE_L, WRITE_WRITE_H,
        DONE_STATE_FINAL
    } state_t;
    state_t state;
    
    // --- Performance Counters (16-bit) ---
    logic [15:0] flops_cnt;
    logic [15:0] reads_cnt;
    logic [15:0] writes_cnt;
    
    // --- LÓGICA DE SINCRONIZACIÓN Y GENERACIÓN DE PULSO DE INICIO ---
    logic start_sync_level; 
    logic start_sync_prev;  
    logic start_proc_pulse_synced; 

    always_ff @(posedge clk or negedge aclr_n) begin // clk es CLOCK_50
        if (!aclr_n) begin
            start_sync_level <= 0;
            start_sync_prev  <= 0;
        end else begin
            start_sync_level <= start_proc_pulse; 
            start_sync_prev  <= start_sync_level;
        end
    end
    assign start_proc_pulse_synced = start_sync_level & (~start_sync_prev); 
    // ----------------------------------------------------------------------
    
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
    logic [2:0] lane_idx;
    // 0..3
    logic [2:0] fetch_step; 

    // Paso: 1.0 / Scale.
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

    // FSM Principal
    always_ff @(posedge clk or negedge aclr_n) begin
        if (!aclr_n) begin
            state <= IDLE;
            busy <= 0; done <= 0;
            dst_x <= 0; dst_y <= 0; src_acc_x <= 0; src_acc_y <= 0;
            mem_we <= 0; mem_addr <= 0; mem_data_out <= 0;
            simd_start <= 0; lane_idx <= 0; fetch_step <= 0;
            temp_src_acc_x <= 0;
            // RESET COUNTERS
            flops_cnt <= 0; reads_cnt <= 0; writes_cnt <= 0;
        end else begin
            if (!step_mode || (step_mode && step_pulse)) begin
                case (state)
                    IDLE: begin
                        done <= 0;
                        simd_start <= 0;
                        if (start_proc_pulse_synced || (step_mode && step_pulse)) begin 
                            state <= INIT; 
                            busy <= 1;
                            // Reset Counters en inicio (en caso de que no haya habido reset)
                            flops_cnt <= 0; reads_cnt <= 0; writes_cnt <= 0;
                        end 
                        else busy <= 0;
                    end

                    INIT: begin
                        dst_x <= 0;
                        dst_y <= 0; src_acc_x <= 0; src_acc_y <= 0;
                        state <= CALC_ADDR;
                    end

                    CALC_ADDR: begin
                        src_y_int = src_acc_y[31:16];
                        if (src_y_int >= cfg_height - 1) src_y_int = cfg_height - 2;
                        if (cfg_mode == 0) begin
                            // MODO SECUENCIAL
                            temp_src_acc_x = src_acc_x;
                            src_x_int = temp_src_acc_x[31:16];
                            fx = {8'b0, temp_src_acc_x[15:8]};
                            if (src_x_int >= cfg_width - 1) src_x_int = cfg_width - 2;
                            fy = {8'b0, src_acc_y[15:8]};
                            state <= REQ_P00;
                        end else begin
                            // MODO SIMD
                            lane_idx <= 0;
                            temp_src_acc_x <= src_acc_x; 
                            state <= SIMD_FETCH_INIT;
                        end
                    end

                    // --- SECUENCIAL CON LATENCIA (4 lecturas = 8 ciclos) ---
                    REQ_P00: begin mem_we<=0;
                        mem_addr <= (src_y_int*cfg_width)+src_x_int; reads_cnt <= reads_cnt + 1; state <= WAIT_P00; end
                    WAIT_P00: begin p00_reg <= mem_data_in; state <= REQ_P10; end 

                    REQ_P10: begin mem_addr <= (src_y_int*cfg_width)+src_x_int+1;
                        reads_cnt <= reads_cnt + 1; state <= WAIT_P10; end
                    WAIT_P10: begin p10_reg <= mem_data_in; state <= REQ_P01; end 
                        
                    REQ_P01: begin mem_addr <= ((src_y_int+1)*cfg_width)+src_x_int;
                        reads_cnt <= reads_cnt + 1; state <= WAIT_P01_A; end
                    WAIT_P01_A: begin p01_reg <= mem_data_in; state <= REQ_P11; end 

                    REQ_P11: begin mem_addr <= ((src_y_int+1)*cfg_width)+src_x_int+1;
                        reads_cnt <= reads_cnt + 1; state <= WAIT_P11; end
                    WAIT_P11: begin p11_reg <= mem_data_in; state <= COMPUTE_SEQ; end 
                        
                    COMPUTE_SEQ: begin 
                        flops_cnt <= flops_cnt + 1; // 1 FLOP por píxel de salida
                        state <= WRITE_SEQ; 
                    end
                        
                    WRITE_SEQ: begin
                        // CORRECCIÓN: Usar el ancho de salida (cfg_width / 2) como stride
                        mem_addr <= 16'h4000 + (dst_y * (cfg_width / 2)) + dst_x; 
                        mem_data_out <= pix_res_seq;
                        mem_we <= 1;
                        writes_cnt <= writes_cnt + 1; // 1 Escritura
                        state <= NEXT_PIXEL;
                    end

                    // --- SIMD FETCH ---
                    SIMD_FETCH_INIT: begin
                        src_x_int = temp_src_acc_x[31:16];
                        fx = {8'b0, temp_src_acc_x[15:8]};
                        if (src_x_int >= cfg_width - 1) src_x_int = cfg_width - 2;
                        fx_vec[lane_idx] <= fx;
                        fy_vec[lane_idx] <= {8'b0, src_acc_y[15:8]};
                        
                        fetch_step <= 0;
                        state <= SIMD_FETCH_REQ;
                    end

                    SIMD_FETCH_REQ: begin
                        mem_we <= 0;
                        // 4 Lecturas por lane (total 16 lecturas si LANES=4)
                        case(fetch_step)
                            0: begin mem_addr<=(src_y_int*cfg_width)+src_x_int; reads_cnt <= reads_cnt + 1; fetch_step<=1; end 
                            1: begin mem_addr<=(src_y_int*cfg_width)+src_x_int+1; reads_cnt <= reads_cnt + 1; fetch_step<=2; end
                            2: begin p00_vec[lane_idx]<=mem_data_in; mem_addr<=((src_y_int+1)*cfg_width)+src_x_int; reads_cnt <= reads_cnt + 1; fetch_step<=3; end 
                            3: begin p10_vec[lane_idx]<=mem_data_in; mem_addr<=((src_y_int+1)*cfg_width)+src_x_int+1; reads_cnt <= reads_cnt + 1; fetch_step<=4; end 
                            4: begin p01_vec[lane_idx]<=mem_data_in; reads_cnt <= reads_cnt + 1; fetch_step<=5; end 
                            5: begin 
                                p11_vec[lane_idx]<=mem_data_in; reads_cnt <= reads_cnt + 1;
                                state <= SIMD_FETCH_WAIT; 
                            end
                        endcase
                    end

                    SIMD_FETCH_WAIT: 
                    begin
                        if (lane_idx == LANES-1) begin
                            state <= COMPUTE_SIMD;
                        end else begin
                            lane_idx <= lane_idx + 1;
                            temp_src_acc_x <= temp_src_acc_x + step_val; 
                            state <= SIMD_FETCH_INIT;
                        end
                    end

                    COMPUTE_SIMD: begin
                        simd_start <= 1;
                        state <= WAIT_SIMD;
                    end

                    WAIT_SIMD: begin
                        simd_start <= 0;
                        if (simd_ready && !simd_start) begin
                            flops_cnt <= flops_cnt + LANES; // N FLOPs por bloque SIMD
                            lane_idx <= 0;
                            state <= WRITE_SIMD_LOOP;
                        end
                    end

                    WRITE_SIMD_LOOP: begin
                        // CORRECCIÓN: Usar el ancho de salida (cfg_width / 2) como stride
                        mem_addr <= 16'h4000 + (dst_y * (cfg_width / 2)) + (dst_x + lane_idx);
                        mem_data_out <= pix_res_vec[lane_idx];
                        mem_we <= 1;
                        writes_cnt <= writes_cnt + 1; // 1 Escritura
                        
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
                            if ((dst_x + LANES) < (cfg_width/2)) begin
                                dst_x <= dst_x + LANES;
                                src_acc_x <= src_acc_x + (step_val << 2);
                                state <= CALC_ADDR;
                            end else begin
                                goto_next_row();
                            end
                        end
                    end

                    DONE_STATE: begin
                        // Inicia la escritura de contadores en MMIO (0xF8 a 0xFD)
                        state <= WRITE_FLOP_L;
                        // BUSY se mantiene ALTO para que la CU tenga el bus
                    end
                    
                    // --- ESCRITURA DE REGISTROS MMIO (0xFFF0 + 8 = 0xFFF8) ---
                    // Flops: F9:F8 | Reads: FB:FA | Writes: FD:FC
                    WRITE_FLOP_L: begin // Escribe F8 (Flops L)
                        mem_we <= 1; mem_addr <= 16'hFFF8; mem_data_out <= flops_cnt[7:0]; state <= WRITE_FLOP_H;
                    end
                    WRITE_FLOP_H: begin // Escribe F9 (Flops H)
                        mem_we <= 1; mem_addr <= 16'hFFF9; mem_data_out <= flops_cnt[15:8]; state <= WRITE_READ_L;
                    end
                    WRITE_READ_L: begin // Escribe FA (Reads L)
                        mem_we <= 1; mem_addr <= 16'hFFFA; mem_data_out <= reads_cnt[7:0]; state <= WRITE_READ_H;
                    end
                    WRITE_READ_H: begin // Escribe FB (Reads H)
                        mem_we <= 1; mem_addr <= 16'hFFFB; mem_data_out <= reads_cnt[15:8]; state <= WRITE_WRITE_L;
                    end
                    WRITE_WRITE_L: begin // Escribe FC (Writes L)
                        mem_we <= 1; mem_addr <= 16'hFFFC; mem_data_out <= writes_cnt[7:0]; state <= WRITE_WRITE_H;
                    end
                    WRITE_WRITE_H: begin // Escribe FD (Writes H)
                        mem_we <= 1; mem_addr <= 16'hFFFD; mem_data_out <= writes_cnt[15:8]; state <= DONE_STATE_FINAL;
                    end
                    
                    DONE_STATE_FINAL: begin
                        mem_we <= 0;
                        busy <= 0; // BAJAR BUSY AQUÍ
                        done <= 1;
                        if (!start_proc_pulse) state <= IDLE;
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
            state <= DONE_STATE; // Inicia la escritura de contadores
        end
    endtask

endmodule