# 200 MHz FPGA TDC Implementation (PLL)

**Author:** Rowan Tyler

---

## Introduction

This folder contains a 200 MHz FPGA implementation of the RC-circuit TDC. An on-chip Phase-Locked Loop (PLL) multiplies the 50 MHz board clock by four to produce a 200 MHz internal clock, giving a time resolution of 5 ns per count — four times finer than the 50 MHz baseline. The state machine, UART transmission protocol, and Raspberry Pi interface are otherwise identical to the 50 MHz design.

This design also adds two improvements over the 50 MHz baseline: a minimum discharge time (to prevent instability at very low resistances) and a transient guard that ignores the `step_input` signal for the first 200 clock cycles after `step_set` is asserted.

---

## Module Overview

| File               | Description                                                                         |
|--------------------|-------------------------------------------------------------------------------------|
| `top.v`            | Top-level state machine, clocked at 200 MHz. Includes debug counter outputs.       |
| `input_timer.v`    | Counts 200 MHz clock cycles. Ignores `step_input` for first 200 cycles (1 µs).     |
| `discharge_timer.v`| Counts down with minimum floor of 2,000,000 cycles (10 ms at 200 MHz).             |
| `PLL_200.v`        | **Wizard-generated.** Altera `altpll` megafunction: 50 MHz → 200 MHz (×4).         |
| `uart.v`           | UART wrapper: instantiates `baud_rate_gen` and `transmitter`.                       |
| `baud_rate_gen.v`  | Divides 200 MHz clock to produce 115200 baud TX clock enable.                       |
| `transmitter.v`    | UART transmitter FSM — serialises one byte at a time.                               |

> **Third-party code:** `baud_rate_gen.v`, `transmitter.v`, and `uart.v` are adapted from the open-source UART-for-FPGA repository by Jamie Iles:  
> [https://github.com/jamieiles/uart](https://github.com/jamieiles/uart)  
> The baud-rate divider constants have been recalculated for 200 MHz. See individual file headers for full details.

> **`PLL_200.v` is auto-generated** by the Quartus MegaWizard and should not be manually edited. To regenerate it, use Tools → IP Catalog → ALTPLL in Quartus Prime.

---

## Key Differences from the 50 MHz Design

| Feature                  | 50 MHz Design         | 200 MHz Design              |
|--------------------------|-----------------------|-----------------------------|
| Clock source             | Board oscillator      | On-chip PLL (×4)            |
| Time resolution          | 20 ns                 | 5 ns                        |
| Transient guard          | None                  | Ignores `step_input` for first 200 cycles (1 µs) |
| Minimum discharge time   | None (5× count only)  | Max(5× count, 2,000,000 cycles = 10 ms) |
| Reset behaviour          | `reset_in` only       | `reset_in` OR PLL not locked |
| Debug outputs            | None                  | LED blink counters, PLL locked signal |

---

## Installation

1. Install **Intel Quartus Prime Lite** (targets the MAX 10 device family).
2. Create a new Quartus project, add all `.v` files from this folder, and set `top.v` as the top-level entity.
3. Assign pin locations in the Pin Planner to match your board:
   - `clk` → 50 MHz oscillator pin (the PLL takes this as input and generates 200 MHz internally)
   - `reset_in` → GPIO connected to Raspberry Pi GPIO 24
   - `enable` → GPIO connected to Raspberry Pi GPIO 23
   - `step_input` → GPIO connected to RC circuit output
   - `step_set` → GPIO connected to RC circuit input
   - `uart_tx` → GPIO connected to Raspberry Pi UART RX (GPIO 15)
   - `dbg_counter_200`, `dbg_counter`, `dbg_pll_locked` → optional LED outputs for debugging
4. Compile and program via JTAG (Tools → Programmer).

> **Note:** The `reset` signal is held active until the PLL reports it has locked (`pll_locked` asserts). The FPGA will not start operating until the PLL is stable, which takes a few microseconds after power-on.

---

## How to Run

Identical to the 50 MHz implementation. Use the scripts in `Raspberry Pi Files/` to drive the measurement cycle. See the top-level `README.md` and `Raspberry Pi Files/README.md` for the full operating procedure.

---

## Technical Details

### PLL Configuration

`PLL_200.v` is configured as follows:

- Input clock: 50 MHz (20,000 ps period)
- Output clock (c0): 200 MHz (multiply × 4, divide × 1)
- Operation mode: NORMAL
- Device family: MAX 10

### Transient Guard

After `step_set` goes high, the `input_timer` ignores `step_input` until the counter exceeds 200 cycles (1 µs at 200 MHz). This prevents noise and capacitive coupling transients on the `step_input` line from causing premature capture immediately after the voltage step is applied.

### Minimum Discharge Time

`discharge_timer` enforces a minimum of 2,000,000 cycles (10 ms at 200 MHz) regardless of the counter value. This prevents a failure mode in which a very short charge time produces a near-zero discharge time, causing the capacitor to still be partially charged at the start of the next measurement.

---

## Known Issues / Future Improvements

- Debug output ports (`dbg_counter_200`, `dbg_counter`, `dbg_pll_locked`, `test`) are present in `top.v` and should be removed or gated for a production build.
- The UART operates at 50 MHz (baud generator divides the 200 MHz clock, but UART timing is based on 200 MHz). Verify baud-rate accuracy if a different clock frequency is used.
