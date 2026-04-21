// =============================================================================
// File   : baud_rate_gen.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : Baud rate generator for a 50 MHz clock. Used in the MPTDC design
//          because the UART subsystem is clocked from the 50 MHz board
//          oscillator (not the 200 MHz PLL) to keep the serial interface
//          independent of the measurement clock domain.
//
//          TX_ACC_MAX = 50,000,000 / 115,200       = 434
//          RX_ACC_MAX = 50,000,000 / (115,200 × 16) = 27
//
// Inputs : clk_50m   — 50 MHz board clock
// Outputs: rxclk_en  — RX clock enable (16× oversampled)
//          txclk_en  — TX clock enable (bit-rate)
//
// Source : Taken unchanged from the open-source UART-for-FPGA repository:
//          https://github.com/jamieiles/uart  (author: Jamie Iles)
//          No modifications made.
// =============================================================================
/*
 * Hacky baud rate generator to divide a 50MHz clock into a 115200 baud
 * rx/tx pair where the rx clcken oversamples by 16x.
 */
module baud_rate_gen(input wire clk_50m,
		     output wire rxclk_en,
		     output wire txclk_en);

parameter RX_ACC_MAX = 50000000 / (115200 * 16);
parameter TX_ACC_MAX = 50000000 / 115200;
parameter RX_ACC_WIDTH = $clog2(RX_ACC_MAX);
parameter TX_ACC_WIDTH = $clog2(TX_ACC_MAX);
reg [RX_ACC_WIDTH - 1:0] rx_acc = 0;
reg [TX_ACC_WIDTH - 1:0] tx_acc = 0;

assign rxclk_en = (rx_acc == 5'd0);
assign txclk_en = (tx_acc == 9'd0);

always @(posedge clk_50m) begin
	if (rx_acc == RX_ACC_MAX[RX_ACC_WIDTH - 1:0])
		rx_acc <= 0;
	else
		rx_acc <= rx_acc + 5'b1;
end

always @(posedge clk_50m) begin
	if (tx_acc == TX_ACC_MAX[TX_ACC_WIDTH - 1:0])
		tx_acc <= 0;
	else
		tx_acc <= tx_acc + 9'b1;
end

endmodule
