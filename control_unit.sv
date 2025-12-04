`timescale 1ns/1ps
import formato_pkg::*;

module control_unit (
    input  logic        clk,
    input  logic        aclr_n,
    input  logic        start_proc_pulse, 
    input  logic        step_mode,
    input  logic        step_pulse,
    input  logic [15:0] cfg_width, cfg_height, cfg_scale, 
    input  logic [7:0]  cfg_mode,
    output logic        busy, done,
    output logic        mem_we,
    output logic [18:0] mem_addr,      
    output logic [7:0]  mem_data_out,
    input  logic [7:0]  mem_data_in
);

    typedef enum logic [4:0] {
        IDLE, INIT, CALC_ADDR,
        REQ_P00, WAIT_P00, REQ_P10, WAIT_P10, REQ_P01, WAIT_P01_A, REQ_P11, WAIT_P11,
        COMPUTE_SEQ, WRITE_SEQ, 
        SIMD_FETCH_INIT, SIMD_FETCH_REQ, SIMD_FETCH_WAIT, 
        COMPUTE_SIMD, WAIT_SIMD, WRITE_SIMD_LOOP,
        NEXT_PIXEL, DONE_STATE, 
        WRITE_FLOP_L, WRITE_FLOP_H, WRITE_READ_L, WRITE_READ_H, WRITE_WRITE_L, WRITE_WRITE_H,
        WRITE_DEBUG_Y, WRITE_DEBUG_ADDR, // Nuevo estado debug
        DONE_STATE_FINAL
    } state_t;
    state_t state;
    
    logic [15:0] flops_cnt, reads_cnt, writes_cnt;
    logic [15:0] dst_x, dst_y;
    logic [31:0] src_acc_x, src_acc_y, temp_src_acc_x;
    logic [15:0] src_x_int, src_y_int;
    q8_8_t       fx, fy;
    logic [31:0] step_val;
    logic [15:0] last_read_addr_debug; // Para guardar la última dirección leída

    // SIMD Signals
    localparam LANES = 4;
    logic [7:0] p00_vec[LANES], p10_vec[LANES], p01_vec[LANES], p11_vec[LANES];
    q8_8_t      fx_vec[LANES],  fy_vec[LANES];
    logic [7:0] pix_res_vec[LANES]; 
    q8_8_t pix_res_q_vec[LANES];
    logic       simd_start, simd_ready;
    logic [2:0] lane_idx, fetch_step; 
    
    // Seq Signals
    logic [7:0] p00_reg, p10_reg, p01_reg, p11_reg, pix_res_seq;

    assign step_val = (cfg_scale == 16'h0080) ? 32'h00020000 : 32'h00010000;

    // Sincronización start
    logic start_s, start_prev, start_pulse;
    always_ff @(posedge clk) begin start_s <= start_proc_pulse; start_prev <= start_s; end
    assign start_pulse = start_s & ~start_prev;

    // Instancias
    interpolacion u_core_seq (.p00(p00_reg), .p10(p10_reg), .p01(p01_reg), .p11(p11_reg), .fx(fx), .fy(fy), .pixel_out(pix_res_seq), .pixel_out_q());
    
    modo_simd #(.LANES(LANES)) u_core_simd (
        .clk(clk), .rst_n(aclr_n), .iniciar(simd_start), .modo_paso(1'b0), .paso(1'b0),
        .ocupado(), .listo(simd_ready),
        .p00_entrada(p00_vec), .p10_entrada(p10_vec), .p01_entrada(p01_vec), .p11_entrada(p11_vec),
        .fx_entrada(fx_vec),   .fy_entrada(fy_vec), .pixel_salida(pix_res_vec), .pixel_salida_q(pix_res_q_vec)
    );

    always_ff @(posedge clk or negedge aclr_n) begin
        if (!aclr_n) begin
            state <= IDLE; busy <= 0; done <= 0;
            dst_x<=0; dst_y<=0; src_acc_x<=0; src_acc_y<=0;
            mem_we<=0; flops_cnt<=0; writes_cnt<=0; reads_cnt<=0;
            last_read_addr_debug <= 0;
        end else begin
            if (!step_mode || (step_mode && step_pulse)) begin
                case (state)
                    IDLE: begin
                        done <= 0; simd_start <= 0;
                        if (start_pulse) begin state <= INIT; busy <= 1; flops_cnt<=0; writes_cnt<=0; reads_cnt<=0; end
                        else busy <= 0;
                    end
                    INIT: begin
                        dst_x<=0; dst_y<=0; src_acc_x<=0; src_acc_y<=0; state <= CALC_ADDR;
                    end
                    CALC_ADDR: begin
                        src_y_int = src_acc_y[31:16];
                        if (src_y_int >= cfg_height - 1) src_y_int = cfg_height - 2;
                        
                        if (cfg_mode == 0) begin 
                            temp_src_acc_x = src_acc_x; src_x_int = temp_src_acc_x[31:16];
                            fx = {8'b0, temp_src_acc_x[15:8]};
                            if (src_x_int >= cfg_width - 1) src_x_int = cfg_width - 2;
                            fy = {8'b0, src_acc_y[15:8]};
                            state <= REQ_P00;
                        end else begin 
                            lane_idx <= 0; temp_src_acc_x <= src_acc_x; state <= SIMD_FETCH_INIT;
                        end
                    end
                    
                    // --- SECUENCIAL ---
                    REQ_P00: begin mem_we<=0; mem_addr <= (src_y_int*cfg_width)+src_x_int; state <= WAIT_P00; end
                    WAIT_P00: begin p00_reg <= mem_data_in; state <= REQ_P10; end 
                    REQ_P10: begin mem_addr <= (src_y_int*cfg_width)+src_x_int+1; state <= WAIT_P10; end
                    WAIT_P10: begin p10_reg <= mem_data_in; state <= REQ_P01; end 
                    REQ_P01: begin mem_addr <= ((src_y_int+1)*cfg_width)+src_x_int; state <= WAIT_P01_A; end
                    WAIT_P01_A: begin p01_reg <= mem_data_in; state <= REQ_P11; end 
                    REQ_P11: begin mem_addr <= ((src_y_int+1)*cfg_width)+src_x_int+1; state <= WAIT_P11; end
                    WAIT_P11: begin p11_reg <= mem_data_in; state <= COMPUTE_SEQ; end 
                    COMPUTE_SEQ: begin flops_cnt++; state <= WRITE_SEQ; end
                    WRITE_SEQ: begin
                        mem_addr <= 19'h40000 + (dst_y * (cfg_width / 2)) + dst_x; 
                        mem_data_out <= pix_res_seq; mem_we <= 1; writes_cnt++; state <= NEXT_PIXEL;
                    end

                    // --- SIMD FETCH ---
                    SIMD_FETCH_INIT: begin
                        src_x_int = temp_src_acc_x[31:16];
                        fx = {8'b0, temp_src_acc_x[15:8]};
                        if (src_x_int >= cfg_width - 1) src_x_int = cfg_width - 2;
                        fx_vec[lane_idx] <= fx;
                        fy_vec[lane_idx] <= {8'b0, src_acc_y[15:8]};
                        fetch_step <= 0; state <= SIMD_FETCH_REQ;
                    end
                    SIMD_FETCH_REQ: begin
                        mem_we <= 0;
                        // Guardamos la dirección para debug
                        last_read_addr_debug <= (src_y_int*cfg_width)+src_x_int;
                        
                        case(fetch_step)
                            0: begin mem_addr<=(src_y_int*cfg_width)+src_x_int; reads_cnt++; fetch_step<=1; end 
                            1: begin mem_addr<=(src_y_int*cfg_width)+src_x_int+1; reads_cnt++; fetch_step<=2; end
                            2: begin 
                                p00_vec[lane_idx]<=mem_data_in; 
                                mem_addr<=((src_y_int+1)*cfg_width)+src_x_int; reads_cnt++; fetch_step<=3; 
                            end 
                            3: begin 
                                p10_vec[lane_idx]<=mem_data_in; 
                                mem_addr<=((src_y_int+1)*cfg_width)+src_x_int+1; reads_cnt++; fetch_step<=4; 
                            end 
                            4: begin p01_vec[lane_idx]<=mem_data_in; reads_cnt++; fetch_step<=5; end 
                            5: begin p11_vec[lane_idx]<=mem_data_in; state <= SIMD_FETCH_WAIT; end
                        endcase
                    end
                    SIMD_FETCH_WAIT: begin
                        if (lane_idx == LANES-1) state <= COMPUTE_SIMD;
                        else begin
                            lane_idx <= lane_idx + 1;
                            temp_src_acc_x <= temp_src_acc_x + step_val; state <= SIMD_FETCH_INIT;
                        end
                    end
                    COMPUTE_SIMD: begin simd_start <= 1; state <= WAIT_SIMD; end
                    WAIT_SIMD: begin
                        simd_start <= 0;
                        if (simd_ready) begin 
                            flops_cnt <= flops_cnt + LANES; lane_idx <= 0; state <= WRITE_SIMD_LOOP;
                        end
                    end
                    WRITE_SIMD_LOOP: begin
                        mem_addr <= 19'h40000 + (dst_y * (cfg_width / 2)) + (dst_x + lane_idx);
                        mem_data_out <= pix_res_vec[lane_idx]; mem_we <= 1; writes_cnt++; 
                        if (lane_idx == LANES-1) state <= NEXT_PIXEL; else lane_idx <= lane_idx + 1;
                    end

                    NEXT_PIXEL: begin
                        mem_we <= 0;
                        // Lógica Unificada
                        if (cfg_mode == 0) begin 
                            if (dst_x < (cfg_width/2) - 1) begin 
                                dst_x <= dst_x + 1; src_acc_x <= src_acc_x + step_val; state <= CALC_ADDR;
                            end else begin
                                dst_x <= 0; src_acc_x <= 0;
                                if (dst_y < (cfg_height/2) - 1) begin
                                    dst_y <= dst_y + 1; src_acc_y <= src_acc_y + step_val; state <= CALC_ADDR;
                                end else state <= DONE_STATE;
                            end
                        end else begin 
                            if ((dst_x + LANES) < (cfg_width/2)) begin
                                dst_x <= dst_x + LANES; src_acc_x <= src_acc_x + (step_val << 2); state <= CALC_ADDR;
                            end else begin
                                dst_x <= 0; src_acc_x <= 0;
                                if (dst_y < (cfg_height/2) - 1) begin
                                    dst_y <= dst_y + 1; src_acc_y <= src_acc_y + step_val; state <= CALC_ADDR;
                                end else state <= DONE_STATE;
                            end
                        end
                    end

                    DONE_STATE: state <= WRITE_FLOP_L;
                    // Escritura Contadores
                    WRITE_FLOP_L: begin mem_we<=1; mem_addr<=19'h58000; mem_data_out<=flops_cnt[7:0]; state<=WRITE_FLOP_H; end
                    WRITE_FLOP_H: begin mem_we<=1; mem_addr<=19'h58001; mem_data_out<=flops_cnt[15:8]; state<=WRITE_READ_L; end
                    WRITE_READ_L: begin mem_we<=1; mem_addr<=19'h58002; mem_data_out<=reads_cnt[7:0]; state<=WRITE_READ_H; end
                    WRITE_READ_H: begin mem_we<=1; mem_addr<=19'h58003; mem_data_out<=reads_cnt[15:8]; state<=WRITE_WRITE_L; end
                    WRITE_WRITE_L: begin mem_we<=1; mem_addr<=19'h58004; mem_data_out<=writes_cnt[7:0]; state<=WRITE_WRITE_H; end
                    WRITE_WRITE_H: begin mem_we<=1; mem_addr<=19'h58005; mem_data_out<=writes_cnt[15:8]; state<=WRITE_DEBUG_Y; end
                    // Debug extra
                    WRITE_DEBUG_Y: begin mem_we<=1; mem_addr<=19'h58008; mem_data_out<=dst_y[7:0]; state<=WRITE_DEBUG_ADDR; end
                    WRITE_DEBUG_ADDR: begin mem_we<=1; mem_addr<=19'h5800A; mem_data_out<=last_read_addr_debug[7:0]; state<=DONE_STATE_FINAL; end
                    
                    DONE_STATE_FINAL: begin
                        mem_we <= 0; busy <= 0; done <= 1;
                        if (!start_pulse) state <= IDLE;
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule