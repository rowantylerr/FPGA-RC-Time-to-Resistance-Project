# Raspberry Pi Control Scripts

**Author:** Rowan Tyler

---

## Introduction

This folder contains the Python scripts that run on the Raspberry Pi to control the FPGA measurement cycle and collect data. Each script drives the same core hardware interface — asserting GPIO signals to reset and enable the FPGA, reading four bytes over UART, and reconstructing the 32-bit counter value — but differs in what it does with the results.

The scripts are intended to be used in sequence: first `timer_fixed_resistor.py` to collect calibration data, then `timer_std_dev_fixed.py` to characterise measurement noise, and finally `timer_stream.py` for live data streaming.

---

## Hardware Interface

| Signal       | Raspberry Pi Pin | GPIO (BCM) | Direction | FPGA Port    |
|--------------|-----------------|------------|-----------|--------------|
| Reset        | Pin 18          | GPIO 24    | Output    | `reset_in`   |
| Enable       | Pin 16          | GPIO 23    | Output    | `enable`     |
| UART RX      | Pin 10          | GPIO 15    | Input     | `uart_tx`    |
| Ground       | Pin 6 (or any GND) | —       | —         | GND          |

The Raspberry Pi hardware UART (`/dev/serial0`) must be enabled and the serial console disabled before running any of these scripts. To configure this:

```bash
sudo raspi-config
# Interface Options → Serial Port → Login shell: No → Serial hardware: Yes
```

Also add `enable_uart=1` to `/boot/config.txt` and reboot.

---

## Script Summary

| Script                    | Purpose                                                              | Output File          |
|---------------------------|----------------------------------------------------------------------|----------------------|
| `timer_fixed_resistor.py` | Collect 100 raw counts per known resistor for calibration data       | `fixed_resistor.txt` |
| `timer_std_dev.py`        | Collect 1000 counts (uses DS3502 digital potentiometer)              | `std_dev_output.txt` |
| `timer_std_dev_fixed.py`  | Collect 1000 counts (fixed resistor, no DS3502)                     | `std_dev_output.txt` |
| `timer_stream.py`         | Stream live counts over TCP to a remote laptop                       | (network only)       |

---

## Installation

```bash
sudo apt-get update
sudo apt-get install python3-pip python3-serial
pip3 install RPi.GPIO pyserial adafruit-circuitpython-ds3502
```

> **Note:** `adafruit-circuitpython-ds3502` is only required by `timer_fixed_resistor.py`, `timer_std_dev.py`, and `timer_stream.py`. These scripts import it but do not use it in their current form — it is a leftover import from an earlier version that used a DS3502 digital potentiometer. It can be safely ignored if the DS3502 is not connected.

---

## How to Run

### Calibration Data Collection (`timer_fixed_resistor.py`)

Connects known resistors one at a time and records 100 measurements per resistor. Used to generate input data for the calibration scripts.

```bash
python3 timer_fixed_resistor.py
```

The script will prompt for a resistance value, collect 100 FPGA counts, then prompt again. Press `Ctrl+C` to stop. Results are appended to `fixed_resistor.txt` in the format:

```
<resistance_ohms> <count_1> <count_2> ... <count_100>
```

> **Known issue:** This script is missing `GPIO.setmode(GPIO.BCM)` and `GPIO.setwarnings(False)` at the top, which are present in the other scripts. Ensure the GPIO mode is set (BCM) before running, or add these lines to the script.

---

### Standard Deviation / Noise Analysis (`timer_std_dev_fixed.py`)

Collects 1000 consecutive measurements from a fixed resistor and writes each count to a file. Used to analyse measurement repeatability and noise.

```bash
python3 timer_std_dev_fixed.py
```

Results are written to `std_dev_output.txt`, one count per line. Invalid readings (0 or >100,000) are automatically re-measured.

---

### Standard Deviation with DS3502 (`timer_std_dev.py`)

Identical to `timer_std_dev_fixed.py` but also initialises a DS3502 I2C digital potentiometer. Use this version if a DS3502 is connected via I2C for variable resistance testing.

```bash
python3 timer_std_dev.py
```

---

### Live TCP Streaming (`timer_stream.py`)

Streams continuous FPGA counts over a TCP socket to a laptop or remote computer for real-time analysis. The laptop must be running a listening server on port 65432.

```bash
python3 timer_stream.py <laptop_ip_address>
```

**Example:**

```bash
python3 timer_stream.py 192.168.1.50
```

On the receiving laptop, a simple Python server can be used to receive the data:

```python
import socket
s = socket.socket()
s.bind(('', 65432))
s.listen(1)
conn, addr = s.accept()
while True:
    data = conn.recv(1024)
    if data:
        print(data.decode(), end='')
```

---

## Technical Details

### Measurement Cycle

Each call to `run_measurement_cycle()` performs the following:

1. Flush the UART receive buffer (discards stale data).
2. Assert `reset_in` high for 10 ms, then low — resets the FPGA state machine.
3. Assert `enable` high — FPGA begins charging the RC circuit.
4. Block on `ser.read(4)` until four UART bytes are received.
5. De-assert `enable` — FPGA enters IDLE state.
6. Reconstruct the 32-bit integer from the four bytes (little-endian, LSB first):

```python
resistance = (data[3] << 24) | (data[2] << 16) | (data[1] << 8) | data[0]
```

### UART Settings

- Port: `/dev/serial0`
- Baud rate: 115200
- Format: 8N1 (8 data bits, no parity, 1 stop bit)
- Timeout: 0.1 s (`timer_fixed_resistor.py`) or 1.0 s (other scripts)

---

## Known Issues / Future Improvements

- `timer_fixed_resistor.py` is missing `GPIO.setmode(GPIO.BCM)` at initialisation — this must be added before use.
- `timer_fixed_resistor.py`, `timer_std_dev.py`, and `timer_stream.py` contain unused imports of `board` and `adafruit_ds3502` — these are left over from an earlier version and can be removed if the DS3502 is not used.
- There is no automatic conversion from raw counts to resistance in any of these scripts — post-processing is done separately using the calibration scripts.
- The TCP streaming server-side listener is not included in this repository; a simple Python socket server is sufficient (see example above).
