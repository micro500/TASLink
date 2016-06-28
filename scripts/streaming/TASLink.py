import os
import serial
import sys
import time
import cmd
import threading
import TASRun

CONTROLLER_NORMAL = 0 # 1 controller
CONTROLLER_Y = 1 #: y-cable [like half a multitap, usually not used by itself]
CONTROLLER_MULTITAP = 2 #: multitap (Ports 1 and 2 only) [snes only]
CONTROLLER_FOUR_SCORE = 3 #: four-score [nes-only peripheral that we don't do anything with]

baud = 2000000

prebuffer = 60
framecount1 = 0
ser = None

TASLINK_CONNECTED = 0 # set to 0 for development without TASLink plugged in, set to 1 for actual testing

consolePorts = [2,0,0,0,0] # 1 when in use, 0 when available. 2 is used to waste cell 0
consoleLanes = [2,0,0,0,0,0,0,0,0] # 1 when in use, 0 when available. 2 is used to waste cell 0
lanes = [[-1],[1,2,5,6],[3,4,7,8],[5,6],[7,8]]
customStreams = [0,0,0,0] # 1 when in use, 0 when available.
customEvents = [0,0,0,0] # 1 when in use, 0 when available.
tasRuns = []
inputBuffers = []

def claimConsolePort(port,type):
	if consolePorts[port] == 0:
		consolePorts[port] = 1 # claim it
		if type is CONTROLLER_NORMAL:
			consoleLanes[lanes[port][0]] = 1
		elif type is CONTROLLER_MULTITAP:
			consoleLanes[lanes[port][0]] = 1
			consoleLanes[lanes[port][1]] = 1
			consoleLanes[lanes[port][2]] = 1
			consoleLanes[lanes[port][3]] = 1
		else:
			consoleLanes[lanes[port][0]] = 1
			consoleLanes[lanes[port][1]] = 1
	
	return True

#TODO: release all corresponding lanes
def releaseConsolePort(port,type):
	if consolePorts[port] == 1:
		consolePorts[port] = 0
		if type is CONTROLLER_NORMAL:
			consoleLanes[lanes[port][0]] = 0
		elif type is CONTROLLER_MULTITAP:
			consoleLanes[lanes[port][0]] = 0
			consoleLanes[lanes[port][1]] = 0
			consoleLanes[lanes[port][2]] = 0
			consoleLanes[lanes[port][3]] = 0
		else:
			consoleLanes[lanes[port][0]] = 0
			consoleLanes[lanes[port][1]] = 0
		return True # we freed the port!
	return False # this means there was no need to free the port in the first place. no harm no foul
		

#TODO: add commands: load, save, etc.
class CLI(cmd.Cmd):
	"""Simple command processor example."""

	def do_exit(self, data):
		return True
		
	def do_new(self, data):
		#get input file
		while True:
			fileName = raw_input("What is the input file (path to filename) ? ")
			if not os.path.isfile(fileName):
				sys.stderr.write('ERROR: File does not exist!\n')
			else:
				break;
		#get ports to use
		while True:
			try:
				breakout = True
				portsList = raw_input("Which physical controller port numbers will you use (1-4, spaces between port numbers)? ")
				portsList = str.split(portsList) # splits by spaces by default
				numControllers = len(portsList)
				for x in range(len(portsList)):
					portsList[x] = int(portsList[x]) # convert each one to an int
					if portsList[x] < 1 or portsList[x] > 4:
						print("ERROR: Port out of range... "+str(portsList[x])+" is not between (1-4)!\n")
						breakout = False
						break
				if any(portsList.count(x) > 1 for x in portsList): # check duplciates
					print("ERROR: One of the ports was listed more than once!\n")
					continue
				if breakout:
					break;
			except ValueError:
				print("ERROR: Please enter integers!\n")
		#get controller type
		while True:
			controllerType = raw_input("What controller type does this run use (normal, y, multitap, four-score)? ")
			if controllerType.lower() != "normal" and controllerType.lower() != "y" and controllerType.lower() != "multitap" and controllerType.lower() != "four-score":
				print("ERROR: Invalid controller type!\n")
			else:
				break;
		if controllerType.lower() == "normal":
			controllerType = CONTROLLER_NORMAL
		elif controllerType.lower() == "y":
			controllerType = CONTROLLER_Y
		elif controllerType.lower() == "multitap":
			controllerType = CONTROLLER_MULTITAP
		elif controllerType.lower() == "four-score":
			controllerType = CONTROLLER_FOUR_SCORE
		#8, 16, 24, or 32 bit
		while True:
			controllerBits = int(raw_input("How many bits of data per controller (8, 16, 24, or 32)? "))
			if controllerBits is not 8 and controllerBits is not 16 and controllerBits is not 24 and controllerBits is not 32:
				print("ERROR: Bits must be either 8, 16, 24, or 32!\n")
			else:
				break;
		#overread value
		while True:
			overread = int(raw_input("Overread value (0 or 1... if unsure choose 0)? "))
			if overread is not 0 and overread is not 1:
				print("ERROR: Overread be either 0 or 1!\n")
				continue
			else:
				break;
		#window mode 0-15.75ms
		while True:
			window = float(raw_input("Window value (0 to disable, otherwise enter time in ms. Must be multiple of 0.25ms. Must be between 0 and 15.75ms)? "))
			if window < 0 or window > 15.25:
				print("ERROR: Window out of range [0, 15.75])!\n")
			elif window%0.25 != 0:
				print("ERROR: Window is not a multiple of 0.25!\n")
			else:
				break;
		#create TASRun object and assign it to our global, defined above
		tasrun = TASRun.TASRun(numControllers,portsList,controllerType,controllerBits,overread,window,fileName)
		tasRuns.append(tasrun)
		
		#automatially discover the next available ports / lanes
		for port in tasrun.portsList: 
			if not claimConsolePort(port,tasrun.controllerType):
				print ("ERROR: Could not claim port ",port)
				#TODO: handle this error more gracefully
		
		#***begin serial communication***
		controllers = list('00000000')
		#set controller lanes and ports
		for port in tasrun.portsList:
			#enable the console ports
			command = "sp"
			command = command + str(port) # should look like 'sp1' now
			if TASLINK_CONNECTED:
				ser.write(command + chr(tasrun.controllerType))
			else:
				print(command,tasrun.controllerType)
			
			#enable the controllers lines
			limit = -1;
			if tasrun.controllerType is CONTROLLER_NORMAL:
				limit = 1
			else:
				limit = 2
			for counter in range(0,limit):
				command = "sc"
				command = command + str(lanes[port][counter]) # should look like 'sc1' now
				controllers[8-lanes[port][counter]] = '1' #this is used later for the custom stream command
				# now we need to set the byte data accordingly
				byte = list('00000000')
				byte[0] = '1' # first set it plugged in
				byte[1] = str(tasrun.overread)# next set overread value
				# set controller size
				if tasrun.controllerBits is 8:
					pass #both bytes should be 0, so we're good
				elif tasrun.controllerBits is 16:
					byte[7] = '1'
				elif tasrun.controllerBits is 24:
					byte[6] = '1'
				elif tasrun.controllerBits is 32:
					byte[6] = '1'
					byte[7] = '1'
				bytestring = "".join(byte) # convert binary to string
				#command = command + chr(int(bytestring,2)) # concatenate the byte data after converting it appropriately
				if TASLINK_CONNECTED:
					ser.write(command + chr(int(bytestring,2))) # send the sc command
				else:
					print(command,bytestring)

		#setup custom stream command
		index = -1
		for counter in range(len(customStreams)):
			if customStreams[counter] == 0:
				index = counter
				break
		if index == -1:
			print("ERROR: all four custom streams are full!")
			#TODO: handle gracefully
		command = 's';
		if index == 0:
			customCommand = 'A'
		elif index == 1:
			customCommand = 'B'
		elif index == 2:
			customCommand = 'C'
		elif index == 3:
			customCommand = 'D'
		bytestring = "".join(controllers) # convert binary to string
		tasrun.setCustomCommand(customCommand) # save the letter this run uses
		command = command + customCommand
		#command = command + chr(int(bytestring,2)) # concatenate the byte data after converting it appropriately
		if TASLINK_CONNECTED:
			ser.write(command + chr(int(bytestring,2))) # send the sA/sB/sC/sD command
		else:
			print(command, bytestring)
			
		#setup events #s e lane_num byte bytestring
		index = -1
		for counter in range(len(customEvents)):
			if customEvents[counter] == 0:
				index = counter
				break
		if index == -1:
			print("ERROR: all four custom events are full!")
			#TODO: handle gracefully
		command = 'se' + str(index)
		#do first byte
		byte = list('{0:08b}'.format(int(tasrun.window/0.25))) # create padded bytestring, convert to list for manipulation
		byte[0] = '1' # enable flag
		byte = "".join(byte) # turn back into string
		#command = command + chr(int(bytestring,2)) # concatenate the second byte data after converting it appropriately
		if TASLINK_CONNECTED:
			ser.write(command + chr(int(byte,2)) + chr(int(bytestring,2))) # send the sA/sB/sC/sD command
		else:
			print(command, byte, bytestring)

		# finnal, clear lanes and get ready to rock
		if TASLINK_CONNECTED:
			ser.write("R")
		else:
			print("R")
		
		inputBuffers.append(tasrun.buffer) #TODO: make this dynamic for 'n' runs, up to 4
		    
	def do_EOF(self, line):
		return True
    
	def postloop(self):
		print

if len(sys.argv) != 2:
  sys.stderr.write('Usage: ' + sys.argv[0] + ' <interface>\n\n')
  sys.exit(0)

if TASLINK_CONNECTED:
	try:
		ser = serial.Serial(sys.argv[1], baud)
	except SerialException:
		print ("ERROR: the specificied interface ("+sys.argv[1]+") is in use")
		sys.exit(0)

#start CLI in its own thread
cli = CLI()
t = threading.Thread(target=cli.cmdloop) # no parens on cmdloop is important... otherwise it blocks
t.start()

# main thread

while not inputBuffers: # wait until we have at least one run ready to go
	pass

def send_frames(index,amount):
	#TODO: actually read index instead of statically having it as 0
	global framecount1
	global ser
	global inputBuffers
	
	if TASLINK_CONNECTED == 1:
		ser.write(''.join(inputBuffers[0][framecount1:(framecount1+amount)]))
	else:
		print(''.join(inputBuffers[0][framecount1:(framecount1+amount)]))
		
	framecount1 = framecount1 + amount

#t3h urn

if TASLINK_CONNECTED == 1:
	send_frames(0,prebuffer)

	while True:
		
		while ser.inWaiting() == 0:
			pass

		c = ser.read()

		if c == 'f' or c == 'g' or c == 'h' or c == 'i': # f is 102
			send_frames(ord(c)-102,1) # 'f' maps to 0, 'g' maps to 1, etc.
		else:
			print (ord(c))

t.join() # block wait until CLI thread terminats
sys.exit(0) # exit cleanly
