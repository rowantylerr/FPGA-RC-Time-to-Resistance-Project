# FPGA RC-Circuit Time-to-Digital Converter (TDC) — Resistance Measurement System

**Author:** Rowan Tyler  
**Project:** 3rd Year Individual Project

---

## Introduction

This project implements a Time-to-Digital Converter (TDC) on an Intel/Altera MAX 10 FPGA to measure an unknown resistance in an RC circuit. The FPGA applies a voltage step to the circuit and counts clock cycles until the capacitor voltage crosses a threshold; this count is directly proportional to the RC time constant and therefore to the unknown resistance. The raw count is transmitted over UART to a Raspberry Pi, where it is converted to a resistance value using calibration data.

Three FPGA implementations are provided, each offering greater measurement precision: a baseline 50 MHz design, a 200 MHz design using an on-chip PLL, and a Multi-Phase TDC (MPTDC) design that achieves approximately 800 MHz effective resolution by summing counter values from four 90°-offset clock phases. Supporting Python scripts handle data collection on the Raspberry Pi, system calibration, and a planned live demonstration application.

---

## Repository Structure

```
GITHUB_SOURCE_CODE/
├── 50 MHz FPGA Files/      # Baseline FPGA design clocked at 50 MHz
├── 200 MHz FPGA Files/     # FPGA design using PLL to run at 200 MHz
├── MPTDC FPGA Files/       # Multi-phase TDC design (~800 MHz effective resolution)
├── Calibration Files/      # Python scripts for system calibration
├── Raspberry Pi Files/     # Python scripts to control the FPGA and collect data
└── Demonstration Files/    # Planned live demonstration application (Pong game)
```

---

## System Architecture

```
  Raspberry Pi                    FPGA (Intel MAX 10)
  ┌────────────────┐             ┌────────────────────────────────┐
  │                │──GPIO 24 ──►│ reset_in                       │
  │                │──GPIO 23 ──►│ enable     ┌──────────────┐    │
  │                │             │            │ State Machine│    │
  │  UART RX ◄─────│─────────────│─uart_tx    │ IDLE         │    │
  │  (/dev/serial0)│             │            │ CHARGING     │    │
  └────────────────┘             │            │ TRANSMITTING │    │
                                 │            │ DISCHARGING  │    │
                                 │            └──────────────┘    │
                                 └────────────────────────────────┘
                                                   │         ▲
                                               step_set      │
                                                   │     step_input
                                                   ▼         │
                                          ┌────────────────────┐
                                          │   RC Circuit       │
                                          │                    │
                                          │  R (unknown) ──┬── │
                                          │                │   │
                                          │  C (~10 nF) ───┘   │
                                          └────────────────────┘
```

The FPGA state machine drives `step_set` high to start charging the RC circuit, counts clock cycles until `step_input` (the capacitor voltage) crosses the FPGA GPIO threshold, then transmits the 32-bit count as four UART bytes (little-endian) before discharging the circuit ready for the next measurement.

---

## Installation

### FPGA — Intel Quartus Prime (Lite Edition)

1. Download and install **Intel Quartus Prime Lite** (free) from the Intel FPGA software download page. This project targets the **Intel MAX 10** device family.
2. Open Quartus Prime and create a new project, selecting the correct MAX 10 device for your board.
3. Add all `.v` files from the relevant FPGA folder (`50 MHz FPGA Files/`, `200 MHz FPGA Files/`, or `MPTDC FPGA Files/`) to the project.
4. Set `top.v` as the top-level entity.
5. Assign pin locations using the **Pin Planner** (Assignments → Pin Planner) to match your board's GPIO header. The key signals are:
   - `clk` — on-board 50 MHz oscillator pin
   - `reset_in` — GPIO input connected to Raspberry Pi GPIO 24
   - `enable` — GPIO input connected to Raspberry Pi GPIO 23
   - `step_input` — GPIO input connected to the RC circuit output
   - `step_set` — GPIO output connected to the RC circuit input
   - `uart_tx` — GPIO output connected to Raspberry Pi UART RX (GPIO 15)
6. Compile the project (Processing → Start Compilation).
7. Program the FPGA via JTAG using the **Programmer** tool (Tools → Programmer).

### Raspberry Pi

Requires Python 3 and the following packages. Run on the Raspberry Pi:

```bash
sudo apt-get update
sudo apt-get install python3-pip python3-serial
pip3 install RPi.GPIO pyserial adafruit-circuitpython-ds3502
```

Enable the hardware UART on the Raspberry Pi by adding `enable_uart=1` to `/boot/config.txt` and disabling the serial console via `raspi-config` (Interface Options → Serial Port → disable console, enable hardware serial).

---

## How to Run

1. Program the FPGA as described above.
2. Connect the hardware:
   - RC circuit between FPGA `step_set` output and `step_input` GPIO
   - FPGA `uart_tx` to Raspberry Pi UART RX pin (GPIO 15 / pin 10)
   - FPGA `reset_in` to Raspberry Pi GPIO 24 (pin 18)
   - FPGA `enable` to Raspberry Pi GPIO 23 (pin 16)
   - Shared ground between FPGA and Raspberry Pi
3. On the Raspberry Pi, run the appropriate script from `Raspberry Pi Files/`:
   - For calibration data collection: `python3 timer_fixed_resistor.py`
   - For noise/repeatability analysis: `python3 timer_std_dev_fixed.py`
   - For live streaming to a laptop: `python3 timer_stream.py <laptop_ip_address>`

Each script will print progress to the terminal and write results to a text file.

---

## Technical Details

### RC Charging Formula

When a voltage step is applied to an RC circuit, the capacitor voltage follows:

```
V(t) = V_supply × (1 - e^(−t / RC))
```

When `V(t)` reaches the FPGA GPIO threshold voltage `V_th = alpha × V_supply`:

```
t_charge = −RC × ln(1 − alpha)
```

Since `t_charge = count × T` (where `T` is the clock period and `count` is the FPGA counter value):

```
R = (count × T) / (C × ln(1 / (1 − alpha)))
```

The calibration scripts in `Calibration Files/` determine the effective values of `C` and `alpha` by fitting against measurements from known resistors.

### UART Protocol

The FPGA transmits one 32-bit unsigned integer per measurement as four bytes over UART at **115200 baud, 8N1**. Byte order is **little-endian** (LSB first):

```
Byte 0: bits  7:0   (least significant)
Byte 1: bits 15:8
Byte 2: bits 23:16
Byte 3: bits 31:24  (most significant)
```

### Implementation Comparison

| Implementation| Clock       | Time Resolution | Notes                               |
|---------------|-------------|-----------------|-------------------------------------|
| 50 MHz        | 50 MHz      | 20 ns           | Simplest design, no PLL             |
| 200 MHz       | 200 MHz     | 5 ns            | Internal PLL (×4), transient guard  |
| MPTDC         | 4× 200 MHz  | ~1.25 ns        | Four 90° phases summed              |

---

## Known Issues / Future Improvements

- Calibration requires manual measurement of known resistors and re-running the calibration scripts each time the hardware configuration changes.
- The 50 MHz design has no minimum discharge-time guard, which can cause instability at very low resistance values (see the 200 MHz and MPTDC designs for the fix).
