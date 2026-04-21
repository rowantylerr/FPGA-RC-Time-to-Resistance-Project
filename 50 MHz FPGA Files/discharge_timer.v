// =============================================================================
// File   : discharge_timer.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : Countdown timer that gives the RC circuit sufficient time to
//          discharge between measurements. Counts down from 5× the charge
//          count, giving approximately five RC time constants before the
//          next measurement begins.
//
// Inputs : clk     — 50 MHz clock
//          reset   — Active-high synchronous reset
//          clear   — Resets the countdown (used after discharge completes)
//          start   — Assert to begin the discharge countdown
//          counter — 24-bit charge count from input_timer (sets countdown length)
//
// Outputs: finished — Asserted when the countdown reaches zero
// =============================================================================

module discharge_timer(start, clk, reset, counter, finished, clear);

    input clk;
    input reset;
    input start;              // begin discharge after a measurement
    input clear;
    input [23:0] counter;     // charge count from input_timer; sets countdown length
    output reg finished = 1'b0;

    reg started = 1'b0;
    reg [23:0] countdown = 24'd0;

    always @(posedge clk) begin

        if (clear || reset) begin
            countdown <= 24'd0;
            finished <= 1'b0;
            started <= 1'b0;
        end

        else if (start && !finished) begin

            if (!started) begin
                countdown <= counter * 5;  // 5 RC time constants
                started <= 1'b1;
            end

            else begin
                countdown <= countdown - 1;

                if (countdown == 24'd1) begin
                    finished <= 1'b1;
                end
                else begin
                    finished <= 1'b0;
                end
            end
        end

        else begin
            countdown <= countdown;
            finished <= finished;
        end
    end

endmodule
