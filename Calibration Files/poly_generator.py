# =============================================================================
# File        : poly_generator.py
# Project     : FPGA RC-Circuit Resistance Measurement TDC
# Author      : Rowan Tyler
# Description : Fits a second-order polynomial to (FPGA count, resistance)
#               calibration data using NumPy least-squares regression.
#               Outputs the three coefficients (A, B, C) and R² fit quality,
#               ready to copy into a resistance-calculation script.
#
# Input files : A plain-text counts file (one mean FPGA count per line) and
#               a plain-text resistance file (one known resistance in ohms
#               per line), in matching order.
#
# Dependencies: numpy
# Usage       : Edit COUNTS_FILE and RESISTANCE_FILE constants, then run:
#                   python3 poly_generator.py
# =============================================================================

import numpy as np

#COUNTS_FILE = "fpga_counts.txt"
COUNTS_FILE = "200_MPTDC_fixed_fpga_counts.txt"

#RESISTANCE_FILE = "resistance_values.txt"
RESISTANCE_FILE = "fixed_resistance_values.txt"


def main():
    counts = np.loadtxt(COUNTS_FILE, dtype=float)
    resistances = np.loadtxt(RESISTANCE_FILE, dtype=float)

    if counts.shape != resistances.shape:
        raise ValueError(
            f"Count of entries mismatch: {counts.shape} counts vs {resistances.shape} resistances"
        )

    # Second-order polynomial regression: resistance = a*counts^2 + b*counts + c
    coeffs = np.polyfit(counts, resistances, deg=2)
    a, b, c = coeffs

    # Evaluate fit quality
    predicted = np.polyval(coeffs, counts)
    residuals = resistances - predicted
    ss_res = np.sum(residuals ** 2)
    ss_tot = np.sum((resistances - np.mean(resistances)) ** 2)
    r_squared = 1 - ss_res / ss_tot

    print("Second-Order Polynomial Regression Results")
    print("==========================================")
    print(f"A_COEFF = {a:.9e}")
    print(f"B_COEFF = {b:.10e}")
    print(f"C_COEFF = {c:.10e}")
    print(f"\nR² = {r_squared:.10f}")

    print("\nFit Verification")
    print("--------------------------------------------------")
    print(f"{'Counts':>12}  {'Actual (Ω)':>12}  {'Predicted (Ω)':>14}  {'Error (Ω)':>10}")
    print("-" * 54)
    for cnt, actual, pred in zip(counts, resistances, predicted):
        print(f"{cnt:>12.2f}  {actual:>12.1f}  {pred:>14.4f}  {pred - actual:>10.4f}")

    print("\nCopy these into poly_calculated.py:")
    print(f"A_COEFF = {a:.9e}")
    print(f"B_COEFF = {b:.10e}")
    print(f"C_COEFF = {c:.10e}")


main()
