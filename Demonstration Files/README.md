# Demonstration Files

**Author:** Rowan Tyler

---

## Introduction

This folder contains demonstration software for the RC-circuit TDC project. The intended demonstration is a live, interactive Pong game in which the resistance measured by the FPGA directly controls paddle movement — providing a tangible, real-time visualisation of the measurement system in action. 

> **Third-party code:** The source code for the pong game was taken from a repository by DavidSerranoFranco:  
> [https://github.com/DavidSerranoFranco/PongGame-Python](https://github.com/DavidSerranoFranco/PongGame-Python)  
> The code was adapted to take a streamed TCP input from the Raspberry Pi, which corresponds to an analogue potentiometers position measured via an FPGA deploying the 50 MHz Verilog system.

The Pong game application (`PongGame-Python-main/`) is currently a standalone game with keyboard and AI controls. **The integration layer that connects the FPGA/Raspberry Pi data stream to the game is not yet implemented** and is planned as a future addition. When complete, the system will work as follows:

```
  RC Circuit           FPGA              Raspberry Pi           Laptop
  ┌──────────┐    ┌──────────┐    ┌────────────────────┐   ┌──────────┐
  │ R (knob) │───►│ TDC      │───►│ timer_stream.py    │──►│ Pong     │
  │ or pot.  │    │ counter  │    │ TCP stream         │   │ game     │
  └──────────┘    └──────────┘    └────────────────────┘   └──────────┘
       ▲                                                        │
       │                    Resistance value                    │
       └──────────────── controls paddle position ◄────────────┘
```

The Raspberry Pi script `timer_stream.py` (in `Raspberry Pi Files/`) already handles the data streaming over TCP. The remaining work is to add a receiver in the Pong game that reads from the TCP socket and maps the resistance value to a paddle position.

---

## Contents

| Path                              | Description                                      |
|-----------------------------------|--------------------------------------------------|
| `PongGame-Python-main/`           | Standalone Pong game (Pygame). Fully functional. |
| `PongGame-Python-main/README.md`  | Full documentation for the Pong game.            |
| `PongGame-Python-main/index.py`   | Main game script.                                |

---

## Installation (Pong Game — Standalone)

Requires Python 3 and Pygame on the laptop or computer running the game:

```bash
pip install pygame
```

---

## How to Run (Standalone)

```bash
cd "Demonstration Files/PongGame-Python-main"
python index.py
```

The game supports 1-player (vs AI) or 2-player mode, with a selectable winning score of 5 or 10 points.

For full instructions, controls, and game details see [`PongGame-Python-main/README.md`](PongGame-Python-main/README.md).

---

## Planned Integration

The following steps are needed to complete the FPGA-controlled demonstration:

1. Add a TCP socket listener to `index.py` that receives resistance values from `timer_stream.py` on the Raspberry Pi.
2. Map the received resistance value to a paddle Y-position (scaling the expected resistance range to the screen height).
3. Replace the keyboard/AI paddle input with this live value.
4. Handle connection loss or invalid data gracefully (fall back to AI control or pause).

---

## Known Issues / Future Improvements

- The FPGA-to-game integration is not yet implemented.
- The resistance-to-paddle mapping will require calibration to match the physical resistance range of the control element (e.g., a potentiometer or variable RC circuit) to the screen dimensions.
