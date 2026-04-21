// =============================================================================
// File   : input_timer.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : 24-bit counter measuring RC circuit charge time in 200 MHz clock
//          cycles (5 ns resolution). Ignores step_input for the first 200
//          cycles after step_set goes high to reject capacitive coupling
//          transients on the input line.
//
// Inputs : clk        — 200 MHz clock (from PLL)
//          reset      — Active-high synchronous reset
//          clear      — Clears the counter between measurements
//          step_set   — High while the RC circuit is being charged
//          step_input — Synchronised threshold-crossing from RC circuit
//
// Outputs: timer_output — Current 24-bit counter value
//          overflow     — Asserted if the counter reaches 0xFFFFFF
// =============================================================================
module input_timer(step_set, step_input, clk, reset, timer_output, overflow, clear);

    input clk;
    input reset;
    input step_input;
    input step_set;
    input clear;

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
            //Also ensure that the counter is larger than a minimum value to avoid transients
            else if (step_input == 1'b1 && counter > 24'd200) begin
                timer_stop <= 1'b1;
            end
        end
    end

    assign timer_output = counter;
    assign overflow = overflow_reg;

endmodule