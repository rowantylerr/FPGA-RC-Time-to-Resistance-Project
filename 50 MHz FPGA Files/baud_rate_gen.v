// =============================================================================
// File   : baud_rate_gen.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : Baud rate generator for a 50 MHz clock. Produces clock-enable
//          strobes for a 115200 baud UART transmitter and a 16× oversampled
//          receiver. One strobe is asserted for a single clock cycle at the
//          appropriate interval.
//
//          TX_ACC_MAX = 50,000,000 / 115,200       = 434  (actual: 115,207 baud)
//          RX_ACC_MAX = 50,000,000 / (115,200 × 16) = 27  (16× oversample)
//
// Inputs : clk_50m   — 50 MHz clock
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
