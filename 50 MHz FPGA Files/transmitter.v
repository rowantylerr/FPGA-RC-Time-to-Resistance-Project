// =============================================================================
// File   : transmitter.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : UART transmitter FSM. Serialises one 8-bit byte at a time using
//          a four-state FSM (IDLE → START → DATA → STOP). Transmission begins
//          when wr_en is pulsed and clken (from baud_rate_gen) gates each bit.
//
// Inputs : clk_50m — 50 MHz clock
//          clken   — TX baud-rate clock enable (from baud_rate_gen)
//          reset   — Active-high synchronous reset; aborts in-flight byte
//          wr_en   — Pulse high to load din and begin transmission
//          din     — 8-bit data byte to transmit
//
// Outputs: tx      — UART serial output line (idle high)
//          tx_busy — High while a byte is being transmitted
//
// Source : Adapted from the open-source UART-for-FPGA repository:
//          https://github.com/jamieiles/uart  (author: Jamie Iles)
// Changes: Added synchronous active-high reset to abort in-flight bytes and
//          return the UART line to idle (high).
// =============================================================================

module transmitter(input wire [7:0] din,
		   input wire wr_en,
		   input wire clk_50m,
		   input wire clken,
		   input wire reset,    // Synchronous active-high reset
		   output reg tx,
		   output wire tx_busy);

initial begin
	 tx = 1'b1;
end

parameter STATE_IDLE	= 2'b00;
parameter STATE_START	= 2'b01;
parameter STATE_DATA	= 2'b10;
parameter STATE_STOP	= 2'b11;

reg [7:0] data = 8'h00;
reg [2:0] bitpos = 3'h0;
reg [1:0] state = STATE_IDLE;

always @(posedge clk_50m) begin
	// Synchronous reset: abort any in-progress byte, drive UART line idle (high)
	if (reset) begin
		state  <= STATE_IDLE;
		tx     <= 1'b1;
		bitpos <= 3'h0;
		data   <= 8'h00;
	end else
	case (state)
	STATE_IDLE: begin
		if (wr_en) begin
			state <= STATE_START;
			data <= din;
			bitpos <= 3'h0;
		end
	end
	STATE_START: begin
		if (clken) begin
			tx <= 1'b0;
			state <= STATE_DATA;
		end
	end
	STATE_DATA: begin
		if (clken) begin
			if (bitpos == 3'h7)
				state <= STATE_STOP;
			else
				bitpos <= bitpos + 3'h1;
			tx <= data[bitpos];
		end
	end
	STATE_STOP: begin
		if (clken) begin
			tx <= 1'b1;
			state <= STATE_IDLE;
		end
	end
	default: begin
		tx <= 1'b1;
		state <= STATE_IDLE;
	end
	endcase
end

assign tx_busy = (state != STATE_IDLE);

endmodule
