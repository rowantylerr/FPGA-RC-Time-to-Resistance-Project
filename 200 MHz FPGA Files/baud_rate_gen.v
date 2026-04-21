// =============================================================================
// File   : baud_rate_gen.v
// Project: FPGA RC-Circuit Resistance Measurement TDC
// Author : Rowan Tyler
// Brief  : Baud rate generator for a 200 MHz clock. Produces clock-enable
//          strobes for a 115200 baud UART transmitter and a 16× oversampled
//          receiver. Constants recalculated from the 50 MHz original.
//
//          TX_ACC_MAX = 200,000,000 / 115,200       = 1736  (actual: 115,207 baud)
//          RX_ACC_MAX = 200,000,000 / (115,200 × 16) = 108
//
// Inputs : clk_200m  — 200 MHz clock (from PLL)
// Outputs: rxclk_en  — RX clock enable (16× oversampled)
//          txclk_en  — TX clock enable (bit-rate)
//
// Source : Adapted from the open-source UART-for-FPGA repository:
//          https://github.com/jamieiles/uart  (author: Jamie Iles)
// Changes: Recalculated accumulator constants for 200 MHz input clock.
//          Port renamed from clk_50m to clk_200m.
// =============================================================================
/*
 * Baud rate generator for a 200MHz clock, producing a 115200 baud
 * tx enable and a 16x oversampled rx enable.
 *
 * TX_ACC_MAX  = 200_000_000 / 115200        = 1736  → actual baud: 115207
 * RX_ACC_MAX  = 200_000_000 / (115200 * 16) =  108  → actual rate: 115741 * 16
 */
module baud_rate_gen(input wire clk_200m,
                     output wire rxclk_en,
                     output wire txclk_en);

parameter RX_ACC_MAX = 200000000 / (115200 * 16);
parameter TX_ACC_MAX = 200000000 / 115200;
parameter RX_ACC_WIDTH = $clog2(RX_ACC_MAX);
parameter TX_ACC_WIDTH = $clog2(TX_ACC_MAX);

reg [RX_ACC_WIDTH - 1:0] rx_acc = 0;
reg [TX_ACC_WIDTH - 1:0] tx_acc = 0;

assign rxclk_en = (rx_acc == {RX_ACC_WIDTH{1'b0}});
assign txclk_en = (tx_acc == {TX_ACC_WIDTH{1'b0}});

always @(posedge clk_200m) begin
    if (rx_acc == RX_ACC_MAX[RX_ACC_WIDTH - 1:0])
        rx_acc <= 0;
    else
        rx_acc <= rx_acc + 1'b1;
end

always @(posedge clk_200m) begin
    if (tx_acc == TX_ACC_MAX[TX_ACC_WIDTH - 1:0])
        tx_acc <= 0;
    else
        tx_acc <= tx_acc + 1'b1;
end

endmodule
