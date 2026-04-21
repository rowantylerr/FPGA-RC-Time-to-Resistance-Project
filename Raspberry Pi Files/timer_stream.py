# =============================================================================
# File        : timer_stream.py
# Project     : FPGA RC-Circuit Resistance Measurement TDC
# Author      : Rowan Tyler
# Description : Live TCP streaming script. Continuously runs FPGA measurement
#               cycles and streams each raw count value over a TCP socket to a
#               remote computer (e.g., a laptop for real-time analysis or the
#               planned Pong game demonstration). Readings of 0 or 8 (known
#               invalid sentinel values) are automatically discarded and
#               re-measured before sending.
#
# Hardware    : Raspberry Pi with FPGA on GPIO 23/24/15.
#               Remote computer must be listening on port 65432.
#
# Dependencies: RPi.GPIO, pyserial, socket
#               (board and adafruit_ds3502 are imported but unused — leftover
#               from an earlier DS3502 variant; safe to ignore)
#
# Usage       : python3 timer_stream.py <remote_ip_address>
#               Example: python3 timer_stream.py 192.168.1.50
#               Press Ctrl+C to stop.
# =============================================================================

import board
import adafruit_ds3502
import RPi.GPIO as GPIO
import time
import socket
import sys
import serial

# --- 1. SETUP & INITIALIZATION ---

# GPIO Setup
GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)

# Socket configuration
LAPTOP_IP = str(sys.argv[1])
PORT = 65432

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

	client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
	print(f"Connecting to {LAPTOP_IP}...")
	client_socket.connect((LAPTOP_IP, PORT))
	print("Connected successfully!")

	while True:

		# Wait a moment
		time.sleep(0.01)

		# Run FPGA measurement
		fpga_resistance = run_measurement_cycle()

		while fpga_resistance == 0 or fpga_resistance == 8:
			time.sleep(0.01)
			fpga_resistance = run_measurement_cycle()

		try:
			message = f"{fpga_resistance}\n"
			client_socket.sendall(message.encode())
		except socket.error as e:
			print(f"Streaming error: {e}")
			break


except KeyboardInterrupt:
	print("\nExiting...")
	client_socket.close()
	GPIO.cleanup()
