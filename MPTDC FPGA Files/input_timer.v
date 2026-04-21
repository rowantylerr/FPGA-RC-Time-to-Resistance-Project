// =============================================================================
// File   : input_timer.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : 24-bit counter for the MPTDC design. Identical in function to the
//          200 MHz variant but adds a `stopped` output that exposes the
//          internal timer_stop register. This allows top.v to synchronise
//          all four phase-domain `stopped` flags into the 0° clock domain
//          before reading counter values, preventing metastability.
//
// Inputs : clk        — 200 MHz clock (one of four phase-shifted instances)
//          reset      — Active-high synchronous reset
//          clear      — Clears the counter between measurements
//          step_set   — High while the RC circuit is being charged
//          step_input — Synchronised threshold-crossing (phase-specific)
//
// Outputs: timer_output — 24-bit counter value (frozen when stopped)
//          overflow     — Asserted if the counter reaches 0xFFFFFF
//          stopped      — Asserted once the timer has captured a value and
//                         frozen; remains high until cleared
// =============================================================================
module input_timer(step_set, step_input, clk, reset, timer_output, overflow, clear, stopped);

    input clk;
    input reset;
    input step_input;
    input step_set;
    input clear;

    output wire [23:0] timer_output;
    output wire overflow;
    output wire stopped;           // stays high from capture until cleared

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
            // Guard: ignore step_input for first 200 cycles (1 us at 200 MHz)
            else if (step_input == 1'b1 && counter > 24'd200) begin
                timer_stop <= 1'b1;
            end
        end
    end

    assign timer_output = counter;
    assign overflow = overflow_reg;
    assign stopped = timer_stop;

endmodule