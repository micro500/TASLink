#!/usr/bin/env python2
import os
import serial
import sys
import time

baud = 2000000

prebuffer = 60
framecount1 = 0

if len(sys.argv) < 3:
  sys.stderr.write('Usage: ' + sys.argv[0] + ' <interface> <replayfile>\n\n')
  sys.exit(0)

if not os.path.exists(sys.argv[2]):
  sys.stderr.write('Error: "' + sys.argv[2] + '" not found\n')
  sys.exit(1)

# open the file 
fh = open(sys.argv[2], 'rb')

# load all data and store in a buffer
buffer1 = []

count = 0
working_string = ""
while True:
  if (count == 0):
    working_string = "A"
  
  b = fh.read(1)

  if (len(b) == 0):
    break
  
  b = chr(~ord(b) & 0xFF)
  working_string = working_string + b
  
  count = count + 1
  if (count == 2):
    working_string = working_string[0:5] 
    buffer1.append(working_string)
    count = 0
 
fh.close()

 
ser = serial.Serial(sys.argv[1], baud)

ser.write("sc1" + chr(0xD0))
ser.write("sc2" + chr(0x00))
ser.write("sc3" + chr(0xD0))
ser.write("sc4" + chr(0x00))
ser.write("sc5" + chr(0x00))
ser.write("sc6" + chr(0x00))
ser.write("sc7" + chr(0x00))
ser.write("sc8" + chr(0x00))

ser.write("sp1" + chr(0x80))
ser.write("sp2" + chr(0x80))
ser.write("sp3" + chr(0x00))
ser.write("sp4" + chr(0x00))

ser.write("se1" + chr(0x80) + chr(0x05))
ser.write("se2" + chr(0x00) + chr(0x00))
ser.write("se3" + chr(0x00) + chr(0x00))
ser.write("se4" + chr(0x00) + chr(0x00))

ser.write("sA" + chr(0x05))

ser.write("R")

  
def send_frames1(amount):
  global framecount1
  ser.write(''.join(buffer1[framecount1:(framecount1+amount)]));
  framecount1 = framecount1 + amount


send_frames1(prebuffer)

while (1):
  while (ser.inWaiting() == 0):
    pass
    
  c = ser.read()

  if (c == 'f'):
    send_frames1(1)
  else:
    print ord(c)
