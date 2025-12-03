// control_unit.sv
// Simple control FSM for Fase 3
// - start_proc_pulse: inicia la operación
// - step_mode, step_pulse: modo stepping (si step_mode==1 solo avanza con step_pulse)
// - busy: mientras procesa
// - done: se levanta 1 ciclo cuando finaliza

module control_unit #(
    parameter integer CYCLES = 200    // número de "pasos" de procesamiento por defecto
)(
    input  logic clk,            // normalmente conecta a tck o a CLOCK_50 (preferible CLOCK_50)
    input  logic aclr_n,         // active low async reset
    input  logic start_proc_pulse,// pulso de arranque (asíncrono respecto a clk; será sincronizado por el módulo)
    input  logic step_mode,      // modo paso-a-paso (1 = stepping)
    input  logic step_pulse,     // pulso que avanza 1 paso cuando step_mode==1

    output logic busy,           // activo mientras corriendo
    output logic done            // pulso 1 ciclo cuando finaliza
);

    // FSM states
    typedef enum logic [1:0] {S_IDLE = 2'b00, S_RUNNING = 2'b01, S_DONE = 2'b10} state_e;
    state_e state, state_n;

    // Internal synchronized start pulse
    logic start_sync, start_sync_d;
    // Counter
    logic [$clog2(CYCLES+1)-1:0] counter;
    logic counter_max;

    // Synchronize asynchronous start_proc_pulse into clk domain (2-stage)
    always_ff @(posedge clk or negedge aclr_n) begin
        if (!aclr_n) begin
            start_sync_d <= 1'b0;
            start_sync   <= 1'b0;
        end else begin
            start_sync_d <= start_proc_pulse;
            start_sync   <= start_sync_d;
        end
    end

    // Counter max detect
    assign counter_max = (counter == CYCLES-1);

    // FSM sequential
    always_ff @(posedge clk or negedge aclr_n) begin
        if (!aclr_n) begin
            state <= S_IDLE;
            counter <= '0;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            state <= state_n;

            // default outputs
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    counter <= '0;
                    busy <= 1'b0;
                    if (start_sync) begin
                        // start requested -> go running (unless cycles==0, then immediate done)
                        if (CYCLES == 0) begin
                            state <= S_DONE;
                            done <= 1'b1;
                        end else begin
                            state <= S_RUNNING;
                            busy <= 1'b1;
                        end
                    end
                end

                S_RUNNING: begin
                    busy <= 1'b1;

                    // decide if we advance a step this cycle:
                    // - if step_mode==0 -> automatic: advance every clk
                    // - if step_mode==1 -> only advance when step_pulse==1
                    if ((!step_mode) || (step_mode && step_pulse)) begin
                        // advance counter
                        if (counter_max) begin
                            // finished
                            counter <= '0;
                            state <= S_DONE;
                            busy <= 1'b0;
                            done <= 1'b1;
                        end else begin
                            counter <= counter + 1;
                        end
                    end
                end

                S_DONE: begin
                    // raise done for one clk (done already set)
                    // wait for start to be deasserted then go to IDLE
                    if (!start_sync) begin
                        state <= S_IDLE;
                        done <= 1'b0;
                        busy <= 1'b0;
                    end
                end

                default: begin
                    state <= S_IDLE;
                    busy <= 1'b0;
                    done <= 1'b0;
                end
            endcase
        end
    end

    // Combinational next-state (kept simple; main sequencing in sequential block)
    always_comb begin
        state_n = state;
    end

endmodule
