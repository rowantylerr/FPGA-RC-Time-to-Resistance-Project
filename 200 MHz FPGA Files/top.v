// =============================================================================
// File   : top.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : Top-level state machine for the 200 MHz TDC implementation.
//          Identical in structure to the 50 MHz design, but clocked from an
//          internal PLL running at 200 MHz (5 ns resolution). Adds a transient
//          guard (ignores step_input for first 200 cycles) and a minimum
//          discharge time (10 ms). Debug counter outputs and PLL locked signal
//          are provided for LED verification during bring-up.
//
// Inputs : clk       — 50 MHz board oscillator (PLL input)
//          reset_in  — Active-high reset (from Raspberry Pi GPIO 24)
//          enable    — Start a measurement cycle (from Raspberry Pi GPIO 23)
//          step_input — Async threshold-crossing signal from RC circuit
//
// Outputs: step_set         — Voltage step output to RC circuit
//          uart_tx          — UART serial output to Raspberry Pi (115200 baud)
//          dbg_counter_200  — 27-bit counter on 200 MHz clock (LED debug)
//          dbg_counter      — 27-bit counter on 50 MHz clock (LED debug)
//          dbg_pll_locked   — Mirrors pll_locked signal (LED debug)
//          test             — Tied high (pin connectivity check)
// =============================================================================
module top(
    input clk,          // 50 MHz board clock
    input reset_in,     //From raspberry pi
    input enable,       //From raspberry pi
    input step_input,   // Async input from RC circuit

    output reg step_set,    //Output to stimulate circuit
    output wire uart_tx,     //Serial output pin for resistance measurement
	 output reg [26:0] dbg_counter_200 = 0,
	 output reg [26:0] dbg_counter = 0,
	 output wire dbg_pll_locked,
	 output wire test = 1
);

	// === DEBUG: LED blinker to verify PLL clock rate ===
	always @(posedge clk_200) begin
		 if (reset)
			  dbg_counter_200 <= 0;
		 else
			  dbg_counter_200 <= dbg_counter_200 + 1;
	end
	
	always @(posedge clk) begin
		 if (reset)
			  dbg_counter <= 0;
		 else
			  dbg_counter <= dbg_counter + 1;
	end
	
	assign dbg_pll_locked = pll_locked;
	assign test = 1;

    // --- PLL: generate 200 MHz internal clock ---
    wire clk_200;
    wire pll_locked;

    PLL_200 pll_inst(
        .areset (1'b0),
        .inclk0 (clk),
        .c0     (clk_200),
        .locked (pll_locked)
    );

    // Hold everything in reset until the PLL has locked
    wire reset = reset_in | ~pll_locked;

    // --- ENSURE STEP_INPUT IS STABLE (synchronise to 200 MHz domain) ---
    reg step_input_meta;   // First FF: may go metastable
    reg step_input_sync;   // Second FF: stable output

    always @(posedge clk_200) begin
        if (reset) begin
            step_input_meta <= 1'b0;
            step_input_sync <= 1'b0;
        end else begin
            step_input_meta <= step_input;
            step_input_sync <= step_input_meta;
        end
    end

    // --- INTERNAL SIGNALS ---
    wire [23:0] counter;
    wire overflow;
    wire discharge_finished;

    // Timer controls
    reg clear_timer;
    reg discharge_start;

    parameter   IDLE 	        = 0,
                CHARGING 	    = 1,
                DISCHARGING     = 2,
                TRANSMITTING    = 3,
                ERROR           = 4;

	reg [2:0] state;

    reg [2:0] tx_stage;
    reg [7:0] uart_din;
    reg uart_wr_en;
    wire uart_tx_busy;

    reg [31:0] calc_resistance;

    // --- MODULE INSTANTIATIONS ---

    //Using step_input_sync as stable input
    input_timer input_timer_inst(
        .step_set(step_set),
        .step_input(step_input_sync),
        .clk(clk_200),
        .reset(reset),
        .timer_output(counter),
        .overflow(overflow),
        .clear(clear_timer)
    );

    discharge_timer discharge_timer_inst(
        .start(discharge_start),
        .clk(clk_200),
        .reset(reset),
        .counter(counter),
        .finished(discharge_finished),
        .clear(clear_timer)
    );

    // UART transmission (clocked at 200 MHz; baud_rate_gen divides down to 115200)
    uart uart_module(
        .din(uart_din),
        .wr_en(uart_wr_en),
        .clk_200m(clk_200),
        .reset(reset),
        .tx(uart_tx),
        .tx_busy(uart_tx_busy)
    );

    // --- MAIN STATE MACHINE ---

    always @(posedge clk_200) begin

        if (reset) begin
            step_set <= 1'b0;
            calc_resistance <= 32'd0;

            state <= CHARGING;

            clear_timer <= 1'b0;
            uart_din <= 8'd0;
            uart_wr_en <= 1'b0;
            tx_stage <= 3'b0;

            discharge_start <= 1'b0;

        end

        else if (enable) begin

            case (state)

                IDLE : begin
                    discharge_start <= 1'b0;
                    clear_timer <= 1'b0;
                    step_set <= 1'b0;
                end

                CHARGING : begin
                    clear_timer <= 1'b0;
                    discharge_start <= 1'b0;
                    step_set <= 1'b1; // Turn on output to charge RC

                    //If overflow occurs, transmit max value
                    if (overflow) begin
                        calc_resistance <= 32'h0;
                        state <= TRANSMITTING;
                    end

                    // Guard: ignore step_input for first 200 cycles to reject coupling transients
						  if (step_input_sync && counter > 24'd200) begin
                        step_set <= 1'b0;
                        calc_resistance <= {8'b0, counter};
                        state <= TRANSMITTING;
                        tx_stage <= 0;
                    end
                end

                // --- TRANSMITTING STATE ---
                TRANSMITTING : begin
                    case (tx_stage)

                        // Step 0: Send first 8 bits
                        0 : begin
                            uart_din <= calc_resistance[7:0];
                            uart_wr_en <= 1'b1;

                            // Wait for transmitter to assert busy
                            if (uart_tx_busy) begin
                                uart_wr_en <= 1'b0;
                                tx_stage <= 1;
                            end
                        end

                        // Step 1: Wait for Byte to finish transmitting
                        1 : begin
                            if (!uart_tx_busy) begin
                                uart_din <= calc_resistance[15:8];
                                uart_wr_en <= 1'b1;
                                tx_stage <= 2;
                            end
                        end

                        // Step 2: Wait for transmitter to acknowledge new byte
                        2 : begin
                            if (uart_tx_busy) begin
                                uart_wr_en <= 1'b0;
                                tx_stage <= 3;
                            end
                        end

                        // Step 3: Wait for Byte to finish transmitting
                        3 : begin
                            if (!uart_tx_busy) begin
                                uart_din <= calc_resistance[23:16];
                                uart_wr_en <= 1'b1;
                                tx_stage <= 4;
                            end
                        end

                        // Step 4: Wait for transmitter to acknowledge new byte
                        4 : begin
                            if (uart_tx_busy) begin
                                uart_wr_en <= 1'b0;
                                tx_stage <= 5;
                            end
                        end

                        // Step 5: Wait for Byte to finish transmitting
                        5 : begin
                            if (!uart_tx_busy) begin
                                uart_din <= calc_resistance[31:24];
                                uart_wr_en <= 1'b1;
                                tx_stage <= 6;
                            end
                        end

                        // Step 6: Wait for transmitter to acknowledge new byte
                        6 : begin
                            if (uart_tx_busy) begin
                                uart_wr_en <= 1'b0;
                                tx_stage <= 7;
                            end
                        end

                        // Step 7: Wait for Byte to finish transmitting
                        7 : begin
                            if (!uart_tx_busy) begin
                                tx_stage <= 0; // Reset tx_stage for next time
                                state <= DISCHARGING; // Safely move to discharge
                            end
                        end

                        default: begin
                            state <= ERROR;
                            tx_stage <= 0;
                        end

                    endcase
                end

                DISCHARGING : begin
                    step_set <= 1'b0;
                    discharge_start <= 1'b1;

                    if (discharge_finished) begin
                        discharge_start <= 1'b0;
                        clear_timer <= 1'b1;
                        state <= IDLE;
                    end

                end

                ERROR : begin
                    state <= IDLE;
                end

                // --- ANY OTHER STATE ---
                default : begin
                    state <= ERROR;
                end

            endcase
        end

        else begin
            // When not enabled, maintain safe states
            discharge_start <= 1'b0;
            step_set <= 1'b0;
        end
    end

endmodule
