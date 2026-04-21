// =============================================================================
// File   : uart.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : UART wrapper module clocked at 200 MHz. Instantiates baud_rate_gen
//          and transmitter. Receiver is commented out (TX-only).
//
// Inputs : clk_200m — 200 MHz clock (from PLL)
//          reset    — Active-high synchronous reset
//          wr_en    — Pulse high to begin transmitting din
//          din      — 8-bit data byte to transmit
//
// Outputs: tx      — UART serial output line (idle high)
//          tx_busy — High while a byte is being transmitted
//
// Source : Adapted from the open-source UART-for-FPGA repository:
//          https://github.com/jamieiles/uart  (author: Jamie Iles)
// Changes: Clock port renamed from clk_50m to clk_200m. Receiver commented
//          out. Added synchronous active-high reset.
// =============================================================================
module uart(input wire [7:0] din,
	    input wire wr_en,
	    input wire clk_200m,
	    input wire reset,   // Synchronous active-high reset — stops any in-flight byte
	    output wire tx,
	    output wire tx_busy
//	    input wire rx,
//	    output wire rdy,
//	    input wire rdy_clr,
//	    output wire [7:0] dout
		);

//wire rxclk_en, 
wire txclk_en;

baud_rate_gen uart_baud(.clk_200m(clk_200m),
			.rxclk_en(rxclk_en),
			.txclk_en(txclk_en));

transmitter uart_tx(.din(din),
		    .wr_en(wr_en),
		    .clk_200m(clk_200m),
		    .clken(txclk_en),
		    .reset(reset),
		    .tx(tx),
		    .tx_busy(tx_busy));

//receiver uart_rx(
//		.rx(rx),
//		 .rdy(rdy),
//		 .rdy_clr(rdy_clr),
//		 .clk_50m(clk_50m),
//		 .clken(rxclk_en),
//		 .data(dout));

endmodule
