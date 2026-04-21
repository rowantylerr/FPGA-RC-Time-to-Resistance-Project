// =============================================================================
// File   : discharge_timer.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : Countdown timer ensuring the RC circuit fully discharges between
//          measurements. Counts down from the larger of (5 × charge count) or
//          2,000,000 cycles (10 ms at 200 MHz). The minimum floor prevents a
//          failure mode where a very short charge time causes a near-zero
//          discharge period, leaving residual charge for the next measurement.
//
// Inputs : clk     — 200 MHz clock (from PLL)
//          reset   — Active-high synchronous reset
//          clear   — Resets countdown state between measurements
//          start   — Assert to begin the discharge countdown
//          counter — 24-bit charge count from input_timer
//
// Outputs: finished — Asserted when countdown reaches zero
// =============================================================================
module discharge_timer(start, clk, reset, counter, finished, clear);

    input clk;
    input reset;
    input start;
    input clear;    
    input [23:0] counter;  
    output reg finished = 1'b0;

    reg started = 1'b0;
    reg [23:0] countdown = 24'd1;     // Internal register for counting down

    always @(posedge clk) begin
        if (clear || reset) begin
            countdown <= 24'd0;
            finished <= 1'b0;
            started <= 1'b0;
        end

        else if (start && !finished) begin
            if (!started) begin
                // Enforce minimum 10 ms discharge (2,000,000 cycles at 200 MHz)
                countdown <= (counter * 5 < 24'd2_000_000) ? 24'd2_000_000 : counter * 5;
                started <= 1'b1;
            end

            else begin

                countdown <= countdown - 1;
                if (countdown == 24'd0) begin
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