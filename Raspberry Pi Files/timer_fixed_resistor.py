# =============================================================================
# File        : timer_fixed_resistor.py
# Project     : FPGA RC-Circuit Resistance Measurement TDC
# Author      : Rowan Tyler
# Description : Calibration data collection script. Prompts the user to enter
#               a known resistance value, then runs 100 FPGA measurement cycles
#               and appends all raw counts to "fixed_resistor.txt". Repeat for
#               each calibration resistor. The output file is the input to the
#               scripts in Calibration Files/.
#
# Hardware    : Raspberry Pi with FPGA connected via:
#                 GPIO 23 (pin 16) → FPGA enable
#                 GPIO 24 (pin 18) → FPGA reset_in
#                 GPIO 15 (pin 10) → FPGA uart_tx (UART RX)
#
# Dependencies: RPi.GPIO, pyserial
#               (board and adafruit_ds3502 are imported but unused in this
#               version — left over from an earlier DS3502 potentiometer
#               variant and can be ignored if the DS3502 is not connected)
#
# Usage       : python3 timer_fixed_resistor.py
#               Follow prompts; press Ctrl+C to stop. Output: fixed_resistor.txt
# =============================================================================

import board
import adafruit_ds3502
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
ser = serial.Serial('/dev/serial0', 115200, timeout=0.1)

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

	f = open("fixed_resistor.txt", "a")

	while True:

		res_value = int(input("\nPlease Enter the resistor value: "))
		print("Starting Measurement Cycle")

		f.write(f'{res_value} ')

		for i in range(0,100):

			# Wait a moment
			time.sleep(0.01)

			# Run FPGA measurement
			fpga_resistance = run_measurement_cycle()

			while fpga_resistance == None:
				time.sleep(0.01)
				fpga_resistance = run_measurement_cycle()

			f.write('' + repr(fpga_resistance) + ' ')

			if (i % 10) == 0:
				print('' + str(i) + '%, ', end = '', flush = True)

		f.write('\n')

except KeyboardInterrupt:
	f.write('\n')
	print('\n')

	f.close()
	print("\nExiting ...")
	GPIO.cleanup()
