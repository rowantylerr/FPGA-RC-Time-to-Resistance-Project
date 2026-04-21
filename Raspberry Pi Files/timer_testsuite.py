import board
import adafruit_ds3502
import RPi.GPIO as GPIO
import time
import sys
import serial

# --- 1. SETUP & INITIALIZATION ---

# I2C Setup for DS3502
i2c = board.I2C()  # uses board.SCL and board.SDA
ds3502 = adafruit_ds3502.DS3502(i2c)

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
    # 1. Reset the FPGA state machine
    GPIO.output(enable_pin, 0)
    GPIO.output(reset_pin, 1)
    time.sleep(0.01) # Short pulse — long enough (10ms) for any in-flight UART byte
                     # (max 87us at 115200 baud) to finish arriving before we flush.

    GPIO.output(reset_pin, 0)

    # Flush NOW — after reset, so any stray byte the UART was mid-sending
    # (which is unaffected by FPGA reset without the transmitter reset fix)
    # has had time to arrive and can be discarded cleanly.
    ser.reset_input_buffer()

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
        ser.reset_input_buffer()
        time.sleep(0.01)
        return 0

# --- 5. MAIN LOOP ---

print("System Ready. Press Ctrl+C to exit.")

try:

	f = open("testsuite_output.txt", "w")
	print("Finished Wiper Values: ")

	for i in range(0,128):

		wiper_value = i
		print(f'{i}, ', end="", flush=True)

		# Set the resistance
		ds3502.wiper = wiper_value
		f.write(repr(wiper_value) + ' ')

		# Wait a moment for resistance to settle
		time.sleep(0.1)

		for j in range(10):

			# Run FPGA measurement
			fpga_resistance = run_measurement_cycle()

			while fpga_resistance == 0 or fpga_resistance > 130000:
				time.sleep(0.001)
				fpga_resistance = run_measurement_cycle()

			f.write('' + repr(fpga_resistance) + ' ')

		f.write('\n')

	f.write('\n')
	print('\n')

	f.close()
	print("\nFinished. Now Exiting...")
	GPIO.cleanup()

except KeyboardInterrupt:
	f.close()
	print("\nExiting Early...")
	GPIO.cleanup()
