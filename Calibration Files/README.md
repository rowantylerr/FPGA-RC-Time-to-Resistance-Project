# Calibration Scripts

**Author:** Rowan Tyler

---

## Introduction

This folder contains two Python scripts used to calibrate the FPGA TDC system — that is, to find the relationship between the raw FPGA counter value and the actual resistance in ohms. Calibration is performed by measuring a set of known resistors with the FPGA system and recording the corresponding counter values (collected using `Raspberry Pi Files/timer_fixed_resistor.py`), then using these scripts to fit a model.

Two calibration approaches are provided:

1. **`poly_generator.py`** — Fits a second-order polynomial directly to the (count, resistance) data pairs. Simple and accurate over the measured range.
2. **`sweep_cap_ln.py`** — Fits the physical RC charging formula by searching for the effective capacitance and threshold voltage ratio that minimise the maximum percentage error. Produces a model grounded in the underlying physics.

---

## Input File Format

Both scripts read from plain text files in the same directory:

- **Counts file** (e.g. `200_MPTDC_fixed_fpga_counts.txt`): one floating-point FPGA counter value per line, each value being the mean count for a known resistor.
- **Resistance file** (e.g. `fixed_resistance_values.txt`): one floating-point resistance value (in ohms) per line, in the same order as the counts file.

These files are produced by `Raspberry Pi Files/timer_fixed_resistor.py`. After collecting 100 measurements per resistor, compute the mean for each and save to the counts file.

---

## Installation

Requires Python 3 with NumPy:

```bash
pip3 install numpy
```

---

## How to Run

### Polynomial Calibration (`poly_generator.py`)

Edit the file path constants at the top of the script to point to your data files:

```python
COUNTS_FILE = "200_MPTDC_fixed_fpga_counts.txt"
RESISTANCE_FILE = "fixed_resistance_values.txt"
```

Then run:

```bash
python3 poly_generator.py
```

The script prints three polynomial coefficients (`A_COEFF`, `B_COEFF`, `C_COEFF`), an R² fit quality value, and a table comparing actual vs. predicted resistance for each calibration point. Copy the coefficients into your resistance-calculation code.

**Example output:**

```
Second-Order Polynomial Regression Results
==========================================
A_COEFF = 1.234567890e-08
B_COEFF = 1.2345678901e-02
C_COEFF = 1.2345678901e+01

R² = 0.9999876543
```

### RC Parameter Sweep (`sweep_cap_ln.py`)

Edit the file paths in the `find_best_parameters(...)` call at the bottom of the script, then run:

```bash
python3 sweep_cap_ln.py
```

The script performs a grid search over capacitance (5–15 nF) and voltage ratio alpha (0.1–0.9) and prints the combination that minimises the maximum percentage error across all calibration points, along with an additive offset to correct systematic bias.

---

## Technical Details

### Polynomial Model

```
R = A × count² + B × count + C
```

Coefficients are found using NumPy's `polyfit` with degree 2. This model is purely empirical and is accurate within the range of the calibration data, but should not be extrapolated far beyond it.

### RC Physical Model

The RC charging equation gives:

```
R = (count × T) / (C × ln(1 / (1 − alpha))) + offset
```

Where:
- `count` = FPGA counter value (clock cycles)
- `T` = clock period in nanoseconds
- `C` = effective capacitance in nF
- `alpha` = V_threshold / V_supply (the GPIO threshold as a fraction of supply voltage)
- `offset` = mean signed error used to remove systematic bias

`sweep_cap_ln.py` searches for the `C` and `alpha` values that minimise the worst-case percentage error across all calibration points, making this approach more robust and physically interpretable than the polynomial model.

---

## Known Issues / Future Improvements

- The clock period in `sweep_cap_ln.py` is currently fixed at 1.25 ns (corresponding to the MPTDC effective clock). Update `period_range` when using the 50 MHz (20 ns) or single-phase 200 MHz (5 ns) implementations.
- The script currently searches a fixed grid; a more efficient optimiser (e.g. scipy.optimize) could reduce computation time and find a more precise minimum.
- Mean counts per resistor must currently be computed manually before running these scripts. A future improvement would integrate this averaging directly from the raw output of `timer_fixed_resistor.py`.
