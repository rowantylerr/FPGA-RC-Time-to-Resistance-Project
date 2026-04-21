# =============================================================================
# File        : sweep_cap_ln.py
# Project     : FPGA RC-Circuit Resistance Measurement TDC
# Author      : Rowan Tyler
# Description : Grid-search calibration script. Finds the effective capacitance
#               (C) and voltage threshold ratio (alpha = V_th / V_supply) that
#               minimise the maximum percentage error when using the physical
#               RC charging formula to convert FPGA counts to resistance:
#
#                   R = (count × T) / (C × ln(1 / (1 − alpha))) + offset
#
#               An additive offset removes any systematic (DC) bias. The best
#               parameter combination is printed with enough precision to
#               replicate the formula in a spreadsheet or other script.
#               Also provides calculate_resistance() to apply a known set of
#               parameters to a new counts file.
#
# Input files : A plain-text counts file and a plain-text resistance file
#               (matching order, one value per line).
#
# Dependencies: numpy, math
# Usage       : Edit the find_best_parameters() call at the bottom of the
#               file with your data file paths, then run:
#                   python3 sweep_cap_ln.py
# =============================================================================

import numpy as np
import math


def find_best_parameters(count_file, resistance_file):
    """
    Search for the capacitance and voltage-ratio values that minimise the maximum
    percentage error between calculated and measured resistance values.

    RC-circuit formula:
        R = (count * T) / (C * ln(1 / (1 - alpha)))

    where:
        count  = FPGA counter value (clock cycles until voltage threshold is reached)
        T      = clock period (ns)
        C      = capacitance (nF)
        alpha  = voltage ratio (V_threshold / V_supply)

    A mean additive offset is applied to remove any systematic (DC) bias.
    The corrected formula used during measurement is therefore:
        R = (count * T) / (C * ln(1 / (1 - alpha))) + offset
    """
    try:
        counts = np.loadtxt(count_file)           # FPGA counter values (clock cycles)
        meas_resistance = np.loadtxt(resistance_file)  # Known resistance values (ohms)

        # --- Parameter search ranges ---
        capacitance_range   = np.linspace(5, 15, 100)    # Capacitance C in nF
        voltage_ratio_range = np.linspace(0.1, 0.9, 100) # Voltage ratio alpha = V_threshold/V_supply
        period_range        = np.linspace(1.25, 1.25, 1)     # Clock period T in ns (fixed at 20 ns)

        best = {
            'capacitance':    None,
            'voltage_ratio':  None,   # alpha = V_threshold / V_supply
            'time_period':    None,
            'max_perc_error': np.inf,
            'offset':         None,   # additive calibration offset (ohms)
        }

        for period in period_range:
            for capacitance in capacitance_range:
                for voltage_ratio in voltage_ratio_range:

                    # Actual argument passed to ln(): always > 1 for alpha in (0, 1)
                    ln_arg = 1.0 / (1.0 - voltage_ratio)

                    # Vectorised resistance calculation for all measurements at once
                    calc_resistance = (counts * period) / (capacitance * math.log(ln_arg))

                    # Mean signed error used as an additive calibration offset.
                    # offset > 0  → formula underestimates resistance on average.
                    offset = np.mean(meas_resistance - calc_resistance)

                    # Percentage error after applying the offset
                    perc_error = np.abs(
                        (meas_resistance - calc_resistance - offset) / meas_resistance * 100
                    )

                    max_perc_error = np.max(perc_error)

                    if max_perc_error < best['max_perc_error']:
                        best['capacitance']    = capacitance
                        best['voltage_ratio']  = voltage_ratio
                        best['time_period']    = period
                        best['max_perc_error'] = max_perc_error
                        best['offset']         = offset

        # --- Print results with enough precision to replicate in Excel ---
        alpha   = best['voltage_ratio']
        ln_arg  = 1.0 / (1.0 - alpha)

        print("\n" + "=" * 80)
        print("BEST COMBINATION FOUND:")
        print(f"  Capacitance (C):          {best['capacitance']:.8f} nF")
        print(f"  Voltage Ratio (alpha):    {alpha:.8f}  [= V_threshold / V_supply]")
        print(f"  ln argument (1/(1-alpha)): {ln_arg:.8f}  [this is what goes into ln()]")
        print(f"  Clock Period (T):         {best['time_period']:.2f} ns")
        print(f"  Calibration Offset:       {best['offset']:.6f} ohms")
        print(f"  Max Percentage Error:     {best['max_perc_error']:.6f}%")
        print()
        print("  Resistance formula:")
        print("    R = (count x T) / (C x ln(1/(1-alpha))) + offset")
        print("=" * 80)

    except FileNotFoundError:
        print("Error: One of the data files was not found.")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")


def calculate_resistance(voltage_ratio, capacitance, count_file, offset=0.0):
    """
    Calculate resistance from FPGA counter values using known parameters.

    Args:
        voltage_ratio: alpha = V_threshold / V_supply
        capacitance:   Capacitance in nF
        count_file:    Path to file containing FPGA counter values
        offset:        Additive calibration offset in ohms (from find_best_parameters)
    """
    counts = np.loadtxt(count_file)  # FPGA counter values (clock cycles)

    period = 20  # Clock period in ns
    ln_arg = 1.0 / (1.0 - voltage_ratio)  # Argument for the natural log

    # Apply the RC formula plus the calibration offset
    calc_resistance = (counts * period) / (capacitance * math.log(ln_arg)) + offset

    for r in calc_resistance:
        print(r)


# --- Entry point ---
find_best_parameters('200_MPTDC_fixed_fpga_counts.txt', 'fixed_resistance_values.txt')
# find_best_parameters('fpga_counts.txt', 'resistance_values.txt')
# calculate_resistance(0.5687, 8.64, 'fixed_fpga_counts.txt', offset=0.0)
