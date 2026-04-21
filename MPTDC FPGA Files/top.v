// =============================================================================
// File   : top.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : Top-level module for the Multi-Phase TDC (MPTDC) implementation.
//          Four input_timer instances each run on a 200 MHz clock at a
//          different phase offset (0°, 90°, 180°, 270°). The final result is
//          the sum of all four counters, equivalent to a ~800 MHz effective
//          sampling rate (~1.25 ns resolution). The state machine waits for
//          all four timers to assert their `stopped` flag (synchronised into
//          the 0° domain) before reading and transmitting the summed value.
//
// Inputs : clk       — 50 MHz board oscillator (PLL input; UART clock)
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
    output wire test
);

    // === DEBUG: LED blinker to verify PLL clock rate ===
    always @(posedge clk_200_0) begin
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
    assign test = 1'b1;

    // --- SYNCHRONISE ENABLE INTO clk_200_0 DOMAIN ---
    reg enable_meta, enable_sync;

	always @(posedge clk_200_0) begin
		 if (reset) begin
			  enable_meta <= 1'b0;
			  enable_sync <= 1'b0;
		 end else begin
			  enable_meta <= enable;
			  enable_sync <= enable_meta;
		 end
	end

    // --- PLL: generate 4 x 200 MHz internal clocks at 90 deg phase offsets ---
    wire clk_200_0;
    wire clk_200_90;
    wire clk_200_180;
    wire clk_200_270;
    wire pll_locked;

    MPTDC_200 pll_inst(
        .areset (1'b0),
        .inclk0 (clk),
        .c0     (clk_200_0),
        .c1     (clk_200_90),
        .c2     (clk_200_180),
        .c3     (clk_200_270),
        .locked (pll_locked)
    );

    // Hold everything in reset until the PLL has locked
    wire reset = reset_in | ~pll_locked;

    // =========================================================================
    // SYNCHRONIZERS: One 2-FF synchronizer per clock phase
    // Each synchronizer ONLY produces its own sync'd copy of step_input.
    // No state machine control here — that stays in the clk_200_0 domain.
    // =========================================================================
    reg step_input_meta_0,   step_input_sync_0;
    reg step_input_meta_90,  step_input_sync_90;
    reg step_input_meta_180, step_input_sync_180;
    reg step_input_meta_270, step_input_sync_270;

    always @(posedge clk_200_0) begin
        if (reset) begin
            step_input_meta_0 <= 1'b0;
            step_input_sync_0 <= 1'b0;
        end else begin
            step_input_meta_0 <= step_input;
            step_input_sync_0 <= step_input_meta_0;
        end
    end

    always @(posedge clk_200_90) begin
        if (reset) begin
            step_input_meta_90 <= 1'b0;
            step_input_sync_90 <= 1'b0;
        end else begin
            step_input_meta_90 <= step_input;
            step_input_sync_90 <= step_input_meta_90;
        end
    end

    always @(posedge clk_200_180) begin
        if (reset) begin
            step_input_meta_180 <= 1'b0;
            step_input_sync_180 <= 1'b0;
        end else begin
            step_input_meta_180 <= step_input;
            step_input_sync_180 <= step_input_meta_180;
        end
    end

    always @(posedge clk_200_270) begin
        if (reset) begin
            step_input_meta_270 <= 1'b0;
            step_input_sync_270 <= 1'b0;
        end else begin
            step_input_meta_270 <= step_input;
            step_input_sync_270 <= step_input_meta_270;
        end
    end

    // =========================================================================
    // INTERNAL SIGNALS
    // =========================================================================
    wire [23:0] counter_0, counter_90, counter_180, counter_270;
    wire overflow_0;       // Use only phase-0 overflow (all phases overflow together)
    wire stopped_0, stopped_90, stopped_180, stopped_270;
    wire discharge_finished;

    reg clear_timer;
    reg discharge_start;

    parameter   IDLE          = 0,
                CHARGING      = 1,
                DISCHARGING   = 2,
                TRANSMITTING  = 3,
                ERROR         = 4;

    reg [2:0] state;

    reg [2:0] tx_stage;
    reg [7:0] uart_din;
    reg uart_wr_en;
    wire uart_tx_busy;

    reg [31:0] calc_resistance;

    // =========================================================================
    // SYNCHRONIZE "stopped" FLAGS INTO clk_200_0 DOMAIN
    //
    // stopped_90/180/270 are set on their respective clock edges.
    // Since these are phase-shifted versions of the same frequency,
    // a 2-FF synchronizer brings them safely into clk_200_0.
    // Once a timer stops, its stopped flag stays high until clear,
    // so there's no risk of missing a short pulse.
    // =========================================================================
    reg stopped_90_meta,  stopped_90_sync;
    reg stopped_180_meta, stopped_180_sync;
    reg stopped_270_meta, stopped_270_sync;

    always @(posedge clk_200_0) begin
        if (reset || clear_timer) begin
            stopped_90_meta  <= 1'b0;  stopped_90_sync  <= 1'b0;
            stopped_180_meta <= 1'b0;  stopped_180_sync <= 1'b0;
            stopped_270_meta <= 1'b0;  stopped_270_sync <= 1'b0;
        end else begin
            stopped_90_meta  <= stopped_90;   stopped_90_sync  <= stopped_90_meta;
            stopped_180_meta <= stopped_180;  stopped_180_sync <= stopped_180_meta;
            stopped_270_meta <= stopped_270;  stopped_270_sync <= stopped_270_meta;
        end
    end

    // All timers have stopped — counter values are now frozen and safe to read
    wire all_stopped = stopped_0 & stopped_90_sync & stopped_180_sync & stopped_270_sync;

    // =========================================================================
    // TIMER INSTANTIATIONS
    // Each timer runs on its own phase-shifted clock.
    // Each timer independently stops when step_input is seen on its clock edge.
    // =========================================================================
    input_timer input_timer_0(
        .step_set(step_set),
        .step_input(step_input_sync_0),
        .clk(clk_200_0),
        .reset(reset),
        .timer_output(counter_0),
        .overflow(overflow_0),
        .clear(clear_timer),
        .stopped(stopped_0)
    );

    input_timer input_timer_90(
        .step_set(step_set),
        .step_input(step_input_sync_90),
        .clk(clk_200_90),
        .reset(reset),
        .timer_output(counter_90),
        .overflow(),                   // Only check overflow on phase 0
        .clear(clear_timer),
        .stopped(stopped_90)
    );

    input_timer input_timer_180(
        .step_set(step_set),
        .step_input(step_input_sync_180),
        .clk(clk_200_180),
        .reset(reset),
        .timer_output(counter_180),
        .overflow(),
        .clear(clear_timer),
        .stopped(stopped_180)
    );

    input_timer input_timer_270(
        .step_set(step_set),
        .step_input(step_input_sync_270),
        .clk(clk_200_270),
        .reset(reset),
        .timer_output(counter_270),
        .overflow(),
        .clear(clear_timer),
        .stopped(stopped_270)
    );

    discharge_timer discharge_timer_inst(
        .start(discharge_start),
        .clk(clk_200_0),
        .reset(reset),
        .counter(counter_0),
        .finished(discharge_finished),
        .clear(clear_timer)
    );

    uart uart_module(
        .din(uart_din),
        .wr_en(uart_wr_en),
        .clk_50m(clk),
        .reset(reset),
        .tx(uart_tx),
        .tx_busy(uart_tx_busy)
    );

    // =========================================================================
    // MAIN STATE MACHINE — runs entirely on clk_200_0
    //
    // This is the ONLY always block that drives step_set, state, calc_resistance,
    // tx_stage, uart_din, uart_wr_en, clear_timer, discharge_start.
    // =========================================================================
    always @(posedge clk_200_0) begin

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

        else if (enable_sync) begin

            case (state)

                IDLE : begin
                    discharge_start <= 1'b0;
                    clear_timer <= 1'b0;
                    step_set <= 1'b0;
                end

                CHARGING : begin
                    clear_timer <= 1'b0;
                    discharge_start <= 1'b0;
                    step_set <= 1'b1;

                    if (overflow_0) begin
                        calc_resistance <= 32'h0;
                        state <= TRANSMITTING;
                        tx_stage <= 0;
                    end

                    // Wait for ALL four timers to stop.
                    // Once all_stopped is high, all counter values are frozen
                    // and safe to read across clock domains.
                    else if (all_stopped) begin
                        step_set <= 1'b0;
                        // Sum of 4 counters: effective 800 MHz count
                        calc_resistance <= {8'b0, counter_0} + {8'b0, counter_90}
                                         + {8'b0, counter_180} + {8'b0, counter_270};
                        state <= TRANSMITTING;
                        tx_stage <= 0;
                    end
                end

                // --- TRANSMITTING STATE ---
                TRANSMITTING : begin
                    case (tx_stage)

                        0 : begin
                            uart_din <= calc_resistance[7:0];
                            uart_wr_en <= 1'b1;
                            if (uart_tx_busy) begin
                                uart_wr_en <= 1'b0;
                                tx_stage <= 1;
                            end
                        end

                        1 : begin
                            if (!uart_tx_busy) begin
                                uart_din <= calc_resistance[15:8];
                                uart_wr_en <= 1'b1;
                                tx_stage <= 2;
                            end
                        end

                        2 : begin
                            if (uart_tx_busy) begin
                                uart_wr_en <= 1'b0;
                                tx_stage <= 3;
                            end
                        end

                        3 : begin
                            if (!uart_tx_busy) begin
                                uart_din <= calc_resistance[23:16];
                                uart_wr_en <= 1'b1;
                                tx_stage <= 4;
                            end
                        end

                        4 : begin
                            if (uart_tx_busy) begin
                                uart_wr_en <= 1'b0;
                                tx_stage <= 5;
                            end
                        end

                        5 : begin
                            if (!uart_tx_busy) begin
                                uart_din <= calc_resistance[31:24];
                                uart_wr_en <= 1'b1;
                                tx_stage <= 6;
                            end
                        end

                        6 : begin
                            if (uart_tx_busy) begin
                                uart_wr_en <= 1'b0;
                                tx_stage <= 7;
                            end
                        end

                        7 : begin
                            if (!uart_tx_busy) begin
                                tx_stage <= 0;
                                state <= DISCHARGING;
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

                default : begin
                    state <= ERROR;
                end

            endcase
        end

        else begin
            discharge_start <= 1'b0;
            step_set <= 1'b0;
        end
    end

endmodule