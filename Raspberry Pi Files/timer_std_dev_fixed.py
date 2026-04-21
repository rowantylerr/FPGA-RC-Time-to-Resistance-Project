# =============================================================================
# File        : timer_std_dev_fixed.py
# Project     : FPGA RC-Circuit Resistance Measurement TDC
# Author      : Rowan Tyler
# Description : Noise and repeatability analysis script for a fixed resistor.
#               Collects 1000 consecutive FPGA count measurements and writes
#               each to "std_dev_output.txt" (one per line). Invalid readings
#               (0 or >100,000) are automatically discarded and re-measured.
#               Simplified version of timer_std_dev.py with no DS3502
#               dependency — use this when the resistor is fixed.
#
# Hardware    : Raspberry Pi with FPGA connected via:
#                 GPIO 23 (pin 16) → FPGA enable
#                 GPIO 24 (pin 18) → FPGA reset_in
#                 GPIO 15 (pin 10) → FPGA uart_tx (UART RX)
#
# Dependencies: RPi.GPIO, pyserial
# Usage       : python3 timer_std_dev_fixed.py
#               Output: std_dev_output.txt
# =============================================================================

import RPi.GPIO as GPIO
import time
import sys
import serial

# --- 1. SETUP & INITIALIZATION ---

# GPIO Setup
GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)

# --- 2. PIN DECLARATIONS ---

# Control Signals (Output to FPGA)
enable_pin = 23  # GPIO 23
reset_pin = 24   # GPIO 24

# Initialize Serial Port (GPIO 15 is RXD)
# 115200 baud, 1 second timeout
ser = serial.Serial('/dev/serial0', 115200, timeout=1.0)

# --- 3. GPIO CONFIGURATION ---

# Outputs
GPIO.setup(reset_pin, GPIO.OUT)
GPIO.setup(enable_pin, GPIO.OUT)

# --- 4. FUNCTION DEFINITIONS ---

def run_measurement_cycle():
    """
    Controls the FPGA to run one measurement and returns the result.
    """

    # Flush any old data out of the serial buffer
    ser.reset_input_buffer()

    # 1. Reset the FPGA state machine
    GPIO.output(enable_pin, 0)
    GPIO.output(reset_pin, 1)
    time.sleep(0.01) # Short pulse
    GPIO.output(reset_pin, 0)

    # 2. Start the measurement
    GPIO.output(enable_pin, 1)

    # 3. Wait for UART data to arrive
    data = ser.read(4)

    # 4. Turn off enable (FPGA goes to Idle)
    GPIO.output(enable_pin, 0)

    # 5. Process Data
    if len(data) == 4:
        #Reconstruct the 32-bit integer
        #Here data[0] being the lowest bit and data[4] being highest
        resistance = (data[3] << 24) | (data[2] << 16) | (data[1] << 8) | data[0]
        return resistance
    else:
        print("Error: Serial Read Timeout")
        return None

# --- 5. MAIN LOOP ---

print("System Ready. Press Ctrl+C to exit.")

try:

	f = open("std_dev_output.txt", "w")

	print("Starting Measurement Cycle")

	for i in range(0,1000):

		# Wait a moment
		time.sleep(0.01)

		# Run FPGA measurement
		fpga_resistance = run_measurement_cycle()

		while fpga_resistance == 0  or fpga_resistance > 100000:
			time.sleep(0.01)
			fpga_resistance = run_measurement_cycle()

		f.write('' + repr(fpga_resistance) + '\n')

		if (i % 100) == 0:
			print('' + str(i/10) + '%, ', end = '', flush = True)

	f.write('\n')
	print('\n')

	f.close()
	print("Finished. Now Exiting...")
	GPIO.cleanup()

except KeyboardInterrupt:
	f.close()
	print("\nExiting Early...")
	GPIO.cleanup()
