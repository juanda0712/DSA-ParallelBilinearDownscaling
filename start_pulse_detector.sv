module start_pulse_detector(
    input  logic clk,
    input  logic aclr,
    input  logic start_bit,
    output logic start_pulse
);
    logic prev;

    always_ff @(posedge clk or negedge aclr) begin
        if(!aclr)
            prev <= 1'b0;
        else
            prev <= start_bit;
    end

    assign start_pulse = (~prev) & start_bit;

endmodule
