// =============================================================================
// File   : discharge_timer.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : Identical to the 200 MHz discharge_timer. Counts down from the
//          larger of (5 × charge count) or MIN_DISCHARGE (2,000,000 cycles =
//          10 ms at 200 MHz). Prevents the self-reinforcing failure mode where
//          a very small counter value leads to a near-zero discharge window.
//
// Inputs : clk     — 200 MHz clock (phase-0 domain)
//          reset   — Active-high synchronous reset
//          clear   — Resets countdown state between measurements
//          start   — Assert to begin the discharge countdown
//          counter — 24-bit charge count from phase-0 input_timer
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
    reg [23:0] countdown = 24'd0;

    // Minimum discharge time: 2,000,000 cycles at 200 MHz = 10 ms
    // This prevents the trap where a tiny counter gives near-zero discharge
    localparam MIN_DISCHARGE = 24'd2_000_000;

    always @(posedge clk) begin
        if (clear || reset) begin
            countdown <= 24'd0;
            finished <= 1'b0; 
            started <= 1'b0;  
        end 

        else if (start && !finished) begin
            if (!started) begin
                // Use whichever is larger: counter*5 or the minimum
                if (counter * 5 < MIN_DISCHARGE)
                    countdown <= MIN_DISCHARGE;
                else
                    countdown <= counter * 5;
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