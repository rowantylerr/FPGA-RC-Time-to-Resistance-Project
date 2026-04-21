// =============================================================================
// File   : input_timer.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : 24-bit counter that measures the time from step_set going high to
//          step_input going high. Represents the RC circuit charge time in
//          clock cycles (20 ns per count at 50 MHz).
//
// Inputs : clk        — 50 MHz clock
//          reset      — Active-high synchronous reset
//          clear      — Clears the counter (used between measurements)
//          step_set   — High while the RC circuit is being charged
//          step_input — Goes high when the capacitor voltage crosses the
//                       FPGA GPIO threshold (synchronised externally)
//
// Outputs: timer_output — Current 24-bit counter value
//          overflow     — Asserted if the counter reaches 0xFFFFFF
// =============================================================================

module input_timer(step_set, step_input, clk, reset, timer_output, overflow, clear);

    input clk;
    input reset;
    input clear;
    input step_input;
    input step_set;

    output wire [23:0] timer_output;
    output wire overflow;

    reg [23:0] counter = 24'd0;
    reg timer_stop = 1'b0;
    reg overflow_reg = 1'b0;

    always @(posedge clk) begin
        if (reset || clear) begin
            counter <= 24'd0;
            timer_stop <= 1'b0;
            overflow_reg <= 1'b0;
        end 
        
        else if (step_set && !timer_stop) begin
            counter <= counter + 1;

            if (counter == 24'hFFFFFF) begin
                counter <= 24'd0;
                overflow_reg <= 1'b1;
            end

            else if (step_input == 1'b1) begin
                timer_stop <= 1'b1;
            end
        end
    end

    assign timer_output = counter;
    assign overflow = overflow_reg;

endmodule