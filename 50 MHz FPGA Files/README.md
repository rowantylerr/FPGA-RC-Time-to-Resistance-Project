# 50 MHz FPGA TDC Implementation

**Author:** Rowan Tyler

---

## Introduction

This folder contains the baseline FPGA implementation of the RC-circuit Time-to-Digital Converter (TDC), clocked directly from the MAX 10 board's 50 MHz oscillator with no PLL. The design measures the time for a capacitor to charge to a threshold voltage by counting 50 MHz clock cycles (20 ns resolution), then transmits the result to a Raspberry Pi over UART at 115200 baud.

This implementation is the simplest of the three and serves as the reference design. It has a time resolution of 20 ns per count. For improved resolution see the `200 MHz FPGA Files/` (5 ns) and `MPTDC FPGA Files/` (~1.25 ns) variants.

---

## Module Overview

| File               | Description                                                                 |
|--------------------|-----------------------------------------------------------------------------|
| `top.v`            | Top-level state machine. Controls measurement cycle and UART transmission.  |
| `input_timer.v`    | Counts 50 MHz clock cycles from `step_set` rising edge to `step_input` rising edge. |
| `discharge_timer.v`| Counts down 5× the charge count to allow the RC circuit to fully discharge. |
| `uart.v`           | UART wrapper: instantiates `baud_rate_gen` and `transmitter`.               |
| `baud_rate_gen.v`  | Divides 50 MHz clock to produce 115200 baud TX/RX clock enables.           |
| `transmitter.v`    | UART transmitter FSM — serialises one byte at a time.                       |

> **Third-party code:** `baud_rate_gen.v`, `transmitter.v`, and `uart.v` are taken or adapted from the open-source UART-for-FPGA repository by Jamie Iles:  
> [https://github.com/jamieiles/uart](https://github.com/jamieiles/uart)  
> See individual file headers for details of any modifications made.

---

## State Machine Diagram

```
         reset / power-on
               │
               ▼
           ┌───────┐
     ┌────►│ IDLE  │◄─────────────────────────┐
     │     └───────┘                          │
     │         │ enable high                  │
     │         ▼                              │
     │     ┌──────────┐  overflow             │
     │     │ CHARGING │──────────────────►    │
     │     └──────────┘                  │    │
     │         │ step_input high         │    │
     │         ▼                         ▼    │
     │     ┌─────────────┐         ┌──────────┴──┐
     │     │ TRANSMITTING│────────►│ DISCHARGING │
     │     │  (4 bytes)  │  done   └─────────────┘
     │     └─────────────┘               │ discharge_finished
     │                                   └──────────────────►
     │                                                       │
     └───────────────────────────────────────────────────────┘
                         (clear timer, back to IDLE)
```

---

## Installation

1. Install **Intel Quartus Prime Lite** (targets the MAX 10 device family).
2. Create a new Quartus project, add all `.v` files from this folder, and set `top.v` as the top-level entity.
3. Assign pin locations in the Pin Planner to match your board:
   - `clk` → 50 MHz oscillator pin
   - `reset_in` → GPIO connected to Raspberry Pi GPIO 24
   - `enable` → GPIO connected to Raspberry Pi GPIO 23
   - `step_input` → GPIO connected to RC circuit output
   - `step_set` → GPIO connected to RC circuit input
   - `uart_tx` → GPIO connected to Raspberry Pi UART RX (GPIO 15)
4. Compile and program via JTAG (Tools → Programmer).

---

## How to Run

Once the FPGA is programmed and the hardware is connected, use the scripts in `Raspberry Pi Files/` to drive the measurement cycle. The FPGA waits for `enable` to be asserted before starting. See the top-level `README.md` and `Raspberry Pi Files/README.md` for the full operating procedure.

A single measurement cycle proceeds as follows:

1. Raspberry Pi pulses `reset_in` high briefly, then asserts `enable` high.
2. FPGA drives `step_set` high — RC circuit begins charging.
3. When `step_input` goes high, the counter value is latched.
4. FPGA transmits the 32-bit count as 4 UART bytes (little-endian, LSB first).
5. Raspberry Pi reads 4 bytes and reconstructs the integer.
6. FPGA discharges the RC circuit, then waits for the next cycle.

---

## Technical Details

### Timing

- Clock period: **20 ns** (50 MHz)
- Maximum measurable charge time: 2²⁴ − 1 = 16,777,215 cycles = **335 ms**
- UART baud rate: **115200**, giving a transmission time of ~347 µs per 4-byte packet

### Synchronisation

The asynchronous `step_input` signal is passed through a two-stage flip-flop synchroniser before entering the state machine, to prevent metastability.

### Discharge Time

The discharge timer counts down from `5 × counter_value`, giving the capacitor approximately five RC time constants to discharge — theoretically reducing the residual voltage to less than 1% of the supply.

---

## Known Issues / Future Improvements

- No minimum discharge-time guard: at very low resistance values the counter will be small, giving a very short discharge time and potentially causing measurement instability (fixed in the 200 MHz and MPTDC variants).
- No transient rejection on `step_input`: spurious glitches shortly after `step_set` goes high could cause premature capture (fixed in the 200 MHz and MPTDC variants, which ignore `step_input` for the first 200 clock cycles).
- The UART receiver is present in the original source but has been commented out, as bidirectional communication is not required.
