# Demonstration Files

**Author:** Rowan Tyler

---

## Introduction

This folder contains demonstration software for the RC-circuit TDC project. The intended demonstration is a live, interactive Pong game in which the resistance measured by the FPGA directly controls paddle movement — providing a tangible, real-time visualisation of the measurement system in action.

> **Third-party code:** The Pong game source code was taken from a repository by DavidSerranoFranco:
> [https://github.com/DavidSerranoFranco/PongGame-Python](https://github.com/DavidSerranoFranco/PongGame-Python)
>
> `PongGame-Python-main/index.py` has been adapted to integrate the FPGA/Raspberry Pi data stream. The original keyboard-controlled game was modified to:
> - Receive real-time resistance values from the Raspberry Pi over a TCP socket.
> - Map those values directly to Player 1's paddle Y-position.
> - Display a waiting screen before the game starts, so the Pi must connect first.
>
> All adaptations are clearly marked with `# ADDED`, `# ADAPTED`, and `# ORIGINAL` comments in `index.py`. The header block at the top of that file lists every change made.

The system works as follows:

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

---

## Contents

| Path                              | Description                                                        |
|-----------------------------------|--------------------------------------------------------------------|
| `PongGame-Python-main/`           | Pong game adapted for FPGA/Pi control (Pygame).                   |
| `PongGame-Python-main/README.md`  | Original documentation for the Pong game (from source repository).|
| `PongGame-Python-main/index.py`   | Main game script — adapted from original source (see header).     |
| `TCP_stream_rcv.py`               | Standalone TCP receiver used during development/testing.           |

---

## Installation

Requires Python 3 and Pygame on the laptop or computer running the game.
The `socket` and `threading` modules used for the TCP integration are part of
the Python standard library and require no additional installation.

```bash
pip install pygame
```

---

## How to Run

### With the Raspberry Pi connected (full demonstration)

1. Start `timer_stream.py` on the Raspberry Pi (see `Raspberry Pi Files/`).
2. Run the Pong game on this PC:

```bash
cd "Demonstration Files/PongGame-Python-main"
python index.py
```

3. The game will display a **"Waiting for Raspberry Pi connection..."** screen,
   showing the PC's IP address and port. Enter that IP on the Pi to connect.
4. Once connected, the main menu appears and the game can begin.
   Moving the physical sensor (potentiometer / RC circuit) controls the left paddle.

### Standalone (keyboard only — Player 2 / AI mode)

The Raspberry Pi controls Player 1's paddle only. Player 2 can still be
controlled with the UP/DOWN arrow keys, or the AI opponent can be selected
from the main menu.

---

## Sensor Mapping

Player 1's paddle position is mapped linearly from the Pi sensor value to the
screen height. The expected sensor range is configured at the top of `index.py`:

```python
PI_MIN_VALUE = 0        # Sensor value corresponding to paddle at top
PI_MAX_VALUE = 20000    # Sensor value corresponding to paddle at bottom
```

Adjust these two constants if your physical sensor has a different output range.

---

## Key Configuration Parameters (`index.py`)

| Constant        | Default  | Description                                      |
|-----------------|----------|--------------------------------------------------|
| `PI_PORT`       | `65432`  | TCP port — must match the Pi script.             |
| `PI_MIN_VALUE`  | `0`      | Minimum sensor value (paddle at top of screen).  |
| `PI_MAX_VALUE`  | `20000`  | Maximum sensor value (paddle at bottom of screen).|

---

## Known Issues / Future Improvements

- If the Pi disconnects mid-game, the paddle freezes at its last position. A
  reconnection mechanism or graceful fallback to AI has not been implemented.
