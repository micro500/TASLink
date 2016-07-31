import serial
import sys
from serial import SerialException

baud = 2000000

if len(sys.argv) < 2:
    sys.stderr.write('Usage: ' + sys.argv[0] + ' <interface>\n\n')
    sys.exit(0)

try:
    ser = serial.Serial(sys.argv[1], baud)
except SerialException:
    print ("ERROR: the specified interface (" + sys.argv[1] + ") is in use")
    sys.exit(0)

ser.write("sd0")

sys.exit(0)