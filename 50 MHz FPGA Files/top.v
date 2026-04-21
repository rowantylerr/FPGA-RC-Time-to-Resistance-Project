// =============================================================================
// File   : top.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : Top-level state machine for the 50 MHz TDC implementation.
//          Controls one complete measure-transmit-discharge cycle per enable
//          pulse. Drives step_set to excite the RC circuit, latches the
//          input_timer count when step_input goes high, transmits the 32-bit
//          count as four UART bytes (little-endian), then waits for the RC
//          circuit to discharge before returning to IDLE.
//
// Inputs : clk       — 50 MHz board oscillator
//          reset_in  — Active-high synchronous reset (from Raspberry Pi GPIO 24)
//          enable    — Start a measurement cycle (from Raspberry Pi GPIO 23)
//          step_input — Async threshold-crossing signal from RC circuit
//
// Outputs: step_set  — Voltage step output to RC circuit
//          uart_tx   — UART serial output to Raspberry Pi (115200 baud, 8N1)
// =============================================================================
module top(
    input clk,
    input reset_in,    //From raspberry pi
    input enable,   //From raspberry pi
    input step_input,   // Async input from RC circuit
    
    output reg step_set, //Output to stimulate circuit
    output wire uart_tx    //Serial output pin for resistance measurement
);

    // --- ENSURE STEP_INPUT IS STABLE
    reg step_input_meta;   // First FF: may go metastable
    reg step_input_sync;   // Second FF: stable output

    always @(posedge clk) begin
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
    wire reset = reset_in;

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
        .clk(clk),
        .reset(reset),
        .timer_output(counter),
        .overflow(overflow),
        .clear(clear_timer)
    );

    discharge_timer discharge_timer_inst(
        .start(discharge_start),
        .clk(clk),
        .reset(reset),
        .counter(counter),
        .finished(discharge_finished),
        .clear(clear_timer)
    );

    // UART transmission
    uart uart_module(
        .din(uart_din),
        .wr_en(uart_wr_en),
        .clk_50m(clk),
        .reset(reset),
        .tx(uart_tx),
        .tx_busy(uart_tx_busy)
    );

    // --- MAIN STATE MACHINE ---

    always @(posedge clk) begin

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

                    if (step_input_sync) begin
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
                
                    // Wait for discharge to finish
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

