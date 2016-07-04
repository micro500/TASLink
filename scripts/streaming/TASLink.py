import os
import serial
import sys
import cmd
import threading
import yaml

# import time # used for sleeps in debugging

import rlcompleter,readline # to add support for tab completion of commands
import glob

def complete(text, state):
   return (glob.glob(text+'*')+[None])[state]
   
def complete_nostate(text, *ignored):
   return (glob.glob(text+'*')+[None])

readline.set_completer_delims(' \t\n')
readline.parse_and_bind("tab: complete")
readline.set_completer(complete)

CONTROLLER_NORMAL = 0 # 1 controller
CONTROLLER_Y = 1 #: y-cable [like half a multitap]
CONTROLLER_MULTITAP = 2 #: multitap (Ports 1 and 2 only) [snes only]
CONTROLLER_FOUR_SCORE = 3 #: four-score [nes-only peripheral that we don't do anything with]

baud = 2000000

prebuffer = 60
ser = None

TASLINK_CONNECTED = 0 # set to 0 for development without TASLink plugged in, set to 1 for actual testing

consolePorts = [2,0,0,0,0] # 1 when in use, 0 when available. 2 is used to waste cell 0
consoleLanes = [2,0,0,0,0,0,0,0,0] # 1 when in use, 0 when available. 2 is used to waste cell 0
lanes = [[-1],[1,2,5,6],[3,4,7,8],[5,6],[7,8]]
customStreams = [0,0,0,0] # 1 when in use, 0 when available.
MASKS = 'ABCD'
tasRuns = []
inputBuffers = []
listenPorts = []
frameCounts = [0,0,0,0]

# For all x in [0,4), tasRuns[x] should always correspond to have customStreams[x]. This MAY NOT corresponds to mask 'ABCD'[x] after remove!
# Each tasRuns[x] listens for latch on port listenPorts[x]. Each run is up to frame frameCouts[x].

class TASRun(object):
    
   def __init__(self,num_controllers,ports_list,controller_type,controller_bits,ovr,wndw,file_name,dummy_frames):
      self.numControllers = num_controllers
      self.portsList = ports_list
      self.controllerType = controller_type
      self.controllerBits = controller_bits
      self.overread = ovr
      self.window = wndw
      self.inputFile = file_name
      self.dummyFrames = dummy_frames

      self.fileExtension = file_name.split(".")[-1] # pythonic last elemnt of a list/string/array

      if self.fileExtension == 'r08':
         self.maxControllers = 2
      elif self.fileExtension == 'r16':
         self.maxControllers = 8
      else:
         self.maxControllers = 1 #random default, but truly we need to support other formats

   def getInputBuffer(self, customCommand):
      fh = open(self.inputFile, 'rb')
      buffer = [] # create a new empty buffer
      count = 0
      working_string = ""

      max = int(self.controllerBits/8) * self.numControllers # bytes * number of controllers
      
      # next we take controller type into account
      if self.controllerType == CONTROLLER_Y or self.controllerType == CONTROLLER_FOUR_SCORE:
         max *= 2
      elif self.controllerType == CONTROLLER_MULTITAP:
         max *= 4
         
      # add the dummy frames
      for frame in range(self.dummyFrames):
         working_string = customCommand
         for bytes in range(max):
            working_string += chr(0xFF)
         buffer.append(working_string)
         
      while True:
         if count == 0:
            working_string = customCommand

         b = fh.read(1) # read one byte

         if len(b) == 0: # fail case
            break

         b = ~ord(b) & 0xFF # flip our 1's and 0's to be hardware compliant; mask just to make sure its a byte
         working_string += chr(b)  # add our byte data

         count += 1  # note the odd increment timing to make the next check easier

         if count == max:
            buffer.append(working_string)
            count = 0
            # now ditch bytes from unused controllers as necessary
            for each in range(self.maxControllers-max):
               fh.read(1)

      fh.close()

      return buffer

def setupCommunication(tasrun):
   #claim the ports / lanes
   for port in tasrun.portsList: 
      claimConsolePort(port,tasrun.controllerType)

   #begin serial communication
   controllers = list('00000000')
   #set controller lanes and ports
   for port in tasrun.portsList:
      #enable the console ports
      command = "sp"
      command += str(port) # should look like 'sp1' now
      if TASLINK_CONNECTED:
         ser.write(command + chr(tasrun.controllerType))
      else:
         print(command,tasrun.controllerType)
      
      #enable the controllers lines
      if tasrun.controllerType == CONTROLLER_NORMAL:
         limit = 1
      elif tasrun.controllerType == CONTROLLER_MULTITAP:
         limit = 4
      else:
         limit = 2
      for counter in range(limit):
         command = "sc" + str(lanes[port][counter]) # should look like 'sc1' now
         controllers[8-lanes[port][counter]] = '1' #this is used later for the custom stream command
         # now we need to set the byte data accordingly
         byte = list('00000000')
         byte[0] = '1' # first set it plugged in
         byte[1] = str(tasrun.overread)# next set overread value
         # set controller size
         if tasrun.controllerBits == 8:
            pass #both bytes should be 0, so we're good
         elif tasrun.controllerBits == 16:
            byte[7] = '1'
         elif tasrun.controllerBits == 24:
            byte[6] = '1'
         elif tasrun.controllerBits == 32:
            byte[6] = '1'
            byte[7] = '1'
         bytestring = "".join(byte) # convert binary to string
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
   else:
      customStreams[index] = 1 # mark in use
   command = 's'
   customCommand = MASKS[index]
   controllerMask = "".join(controllers) # convert binary to string
   command += customCommand
   if TASLINK_CONNECTED:
      ser.write(command + chr(int(controllerMask,2))) # send the sA/sB/sC/sD command
   else:
      print(command, controllerMask)
      
   #setup events #s e lane_num byte controllerMask
   command = 'se' + str(min(tasrun.portsList))
   #do first byte
   byte = list('{0:08b}'.format(int(tasrun.window/0.25))) # create padded bytestring, convert to list for manipulation
   byte[0] = '1' # enable flag
   bytestring = "".join(byte) # turn back into string
   if TASLINK_CONNECTED:
      ser.write(command + chr(int(bytestring,2)) + chr(int(controllerMask,2))) # send the sA/sB/sC/sD command
   else:
      print(command, bytestring, controllerMask)

   # finnal, clear lanes and get ready to rock
   if TASLINK_CONNECTED:
      ser.write("r" + chr(int(controllerMask,2)))
   else:
      print("r", controllerMask)
   
   inputBuffers.append(tasrun.getInputBuffer(customCommand)) # add the input buffer to a global list of input buffers

def isConsolePortAvailable(port,type):
   # port check
   if consolePorts[port] != 0: # if port is disabled or in use
      return False
   
   # lane check
   if type == CONTROLLER_NORMAL:
      if consoleLanes[lanes[port][0]]:
         return False
   elif type == CONTROLLER_MULTITAP:
      if port != 1 or port != 2: # multitap only works on ports 1 and 2
         return False
      if any(consoleLanes[lanes[port][x]] for x in range(4)):
         return False
   else: # y-cable or four-score
      if any(consoleLanes[lanes[port][x]] for x in range(2)):
         return False
   
   return True # passed all checks

def claimConsolePort(port,type):
   if consolePorts[port] == 0:
      consolePorts[port] = 1 # claim it
      if type == CONTROLLER_NORMAL:
         consoleLanes[lanes[port][0]] = 1
      elif type == CONTROLLER_MULTITAP:
         for lane in lanes[port]:
            consoleLanes[lane] = 1
      else:
          consoleLanes[lanes[port][0]] = 1		
          consoleLanes[lanes[port][1]] = 1

def releaseConsolePort(port,type):
   if consolePorts[port] == 1:
      consolePorts[port] = 0
      if type == CONTROLLER_NORMAL:
         consoleLanes[lanes[port][0]] = 0
      elif type == CONTROLLER_MULTITAP:
         for lane in lanes[port]:
            consoleLanes[lane] = 0
      else:
          consoleLanes[lanes[port][0]] = 0
          consoleLanes[lanes[port][1]] = 0

# return false exits the function
# return true exits the whole CLI
class CLI(cmd.Cmd):

   prompt = "TASLink> "
   intro = "\nWelcome to the TASLink command-line interface!\nType 'help' for a list of commands.\n"

   def complete(self, text, state):
      if state == 0:
         origline = readline.get_line_buffer()
         line = origline.lstrip()
         stripped = len(origline) - len(line)
         begidx = readline.get_begidx() - stripped
         endidx = readline.get_endidx() - stripped
         
         compfunc = self.custom_comp_func
         self.completion_matches = compfunc(text, line, begidx, endidx)
      try:
         return self.completion_matches[state]
      except IndexError:
         return None
         
   def custom_comp_func(self,text, line, begidx, endidx):
      return self.completenames(text, line, begidx, endidx) + self.completedefault(text, line, begidx, endidx)

   # complete local directory listing
   def completedefault(self, text, *ignored):
      return complete_nostate(text) # get directory when it doesn't know how to autocomplete

   # do not execute the previous command! (which is the default behavior if not overriden
   def emptyline(self):
      return False

   def do_exit(self, data):
      """Not goodbyte but rather so long for a while"""
      return True
   
   def do_save(self, data):
      """Save a run to a file"""
      # print options
      if not tasRuns:
         print("No currently active runs.")
         return False
      self.do_list(None)
      # ask which run to save
      runID = int(raw_input("Which run # do you want to save? "))
      filename = raw_input("Please enter filename: ")

      with open(filename, 'w') as f:
         f.write(yaml.dump(tasRuns[runID-1]))
      
      print("Save complete!")
      
   def do_modify_frames(self, data):
      """Modify the initial blank input frames"""
      # print options
      if not tasRuns:
         print("No currently active runs.")
         return False
      self.do_list(None)
      # ask which run to modify
      try:
         runID = int(raw_input("Which run # do you want to modify? "))
         index = runID-1
         run = tasRuns[index]
         print("The current number of initial blank frames is : "+str(run.dummyFrames))
         frames = int(raw_input("How many initial blank frames do you want? "))
      except ValueError:
            print("ERROR: Please enter integers!\n")
            return False
      difference = frames - run.dummyFrames # positive means we're adding frames, negative means we're removing frames
      run.dummyFrames = frames
      # modify input buffer accordingly
      if difference > 0:
         working_string = MASKS[index]
         max = int(run.controllerBits/8) * run.numControllers # bytes * number of controllers      
         # next we take controller type into account
         if run.controllerType == CONTROLLER_Y or run.controllerType == CONTROLLER_FOUR_SCORE:
            max *= 2
         elif run.controllerType == CONTROLLER_MULTITAP:
            max *= 4
         for bytes in range(max):
            working_string += chr(0xFF)
            
         for count in range(difference):
            inputBuffers[index].insert(0,working_string) # add the correct number of blank input frames
      elif difference < 0: # remove input frames
         inputBuffers[index] = inputBuffers[index][difference:]
      
      print("Run has been updated. Remember to save if you want this change to be permanent!")

   def do_DPCM_fix(self, data):
      """Apply the DPCM fix to each controller in a run"""
      # print options
      if not tasRuns:
         print("No currently active runs.")
         return False
      self.do_list(None)
      runID = int(raw_input("Which run # do you want to apply the DPCM fix? "))
      index = runID - 1
      tasrun = tasRuns[index]
      for port in tasrun.portsList:
         command = "sp"
         command += str(port) # should look like 'sp1' now
         if TASLINK_CONNECTED:
            ser.write(command + chr(tasrun.controllerType+128)) # the +128 sets the high bit, applying the DPCM fix
         else:
            print(command,tasrun.controllerType+128)

   def do_reset(self, data):
      """Reset an active run back to frame 0"""
      # print options
      if not tasRuns:
         print("No currently active runs.")
         return False
      self.do_list(None)
      runID = int(raw_input("Which run # do you want to reset? "))
      index = runID-1
      frameCounts[index] = 0

      # get the lane mask
      controllers = list('00000000')
      tasrun = tasRuns[index]
      if tasrun.controllerType == CONTROLLER_NORMAL:
         limit = 1
      elif tasrun.controllerType == CONTROLLER_MULTITAP:
         limit = 4
      else:
         limit = 2

      for counter in range(limit):
         controllers[8 - lanes[port][counter]] = '1'

      controllerMask = "".join(controllers)  # convert binary to string

      ser.write("r"+ chr(int(controllerMask,2))) # clear the buffer
      send_frames(index,prebuffer) # re-pre-buffer-!
      print("Reset complete!")

   #TODO: This whole command needs careful rewriting
   def do_remove(self, data):
      """Remove one of the current runs. IMPLEMENTATION INCOMPLETE!"""
      # print options
      if not tasRuns:
         print("No currently active runs.")
         return False
      self.do_list(None)
      # ask which run to end
      runID = int(raw_input("Which run # do you want to end? "))
      index = runID-1
      # free ports
      for port in tasRuns[index].portsList:
         releaseConsolePort(port, tasRuns[index].controllerType)
      # free custom stream and event
      customStreams[index] = 0
      # remove input and run from lists
      del inputBuffers[index]
      del tasRuns[index]
      del listenPorts[index]

      # reset frame counts, move them accordingly
      for i in range(index,len(frameCounts)-1): # one less than the hardcoded max of array
         frameCounts[i] = frameCounts[i+1]
      frameCounts[-1] = 0 # max should be 0 no matter what, since we've just removed one and compressed the list
      # TODO: is there a need to update TASLink and let it know the controllers are disconncted?
      # Or is it ok to have it be simply overriden later?
      
      print("Run has been successfully removed!")

   def do_load(self, data):
      """Load a run from a file"""
      if data == "":
         filename = raw_input("Please enter the file to load: ")
      else:
         filename = data
      if not os.path.isfile(filename):
         print("ERROR: File does not exist!")
         return False
      with open(filename, 'r') as f:
         run = yaml.load(f)
      # check for port conflicts
      if not all(isConsolePortAvailable(port,run.controllerType) for port in run.portsList):
         print("ERROR: Requested ports already in use!")
         return False
      tasRuns.append(run)
      listenPorts.append(min(run.portsList))
      setupCommunication(tasRuns[-1])
      if TASLINK_CONNECTED == 1:
         send_frames(len(tasRuns)-1, prebuffer)
      
      print("Run has been successfully loaded!")
      
   def do_list(self, data):
      """List all active runs"""
      if not tasRuns:
         print("No currently active runs.")
         return False
      for index,run in enumerate(tasRuns):
         print("Run #"+str(index+1)+": ")
         print yaml.dump(run)
      pass
   
   def do_new(self, data):
      """Create a new run with parameters specified in the terminal"""
      #get input file
      while True:
         fileName = raw_input("What is the input file (path to filename) ? ")
         if not os.path.isfile(fileName):
            sys.stderr.write('ERROR: File does not exist!\n')
         else:
            break
      #get ports to use
      while True:
         try:
            breakout = True
            portsList = raw_input("Which physical controller port numbers will you use (1-4, spaces between port numbers)? ")
            portsList = map(int, portsList.split()) # splits by spaces, then convert to int
            numControllers = len(portsList)
            for port in portsList:
               if port not in range(1,5): # Top of range is exclusive
                  print("ERROR: Port out of range... "+str(port)+" is not between (1-4)!\n")
                  breakout = False
                  break
               if not isConsolePortAvailable(port,CONTROLLER_NORMAL): # check assuming one lane at first
                  print("ERROR: The main data lane for port "+str(port)+" is already in use!\n")
                  breakout = False
                  break
            if any(portsList.count(x) > 1 for x in portsList): # check duplciates
               print("ERROR: One of the ports was listed more than once!\n")
               continue
            if breakout:
               break
         except ValueError:
            print("ERROR: Please enter integers!\n")
      #get controller type
      while True:
         breakout = True
         controllerType = raw_input("What controller type does this run use ([n]ormal, [y], [m]ultitap, [f]our-score)? ")
         if controllerType.lower() not in ["normal", "y", "multitap", "four-score", "n", "m", "f"]:
            print("ERROR: Invalid controller type!\n")
            continue
            
         if controllerType.lower() == "normal" or controllerType.lower() == "n":
            controllerType = CONTROLLER_NORMAL
         elif controllerType.lower() == "y":
            controllerType = CONTROLLER_Y
         elif controllerType.lower() == "multitap" or controllerType.lower() == "m":
            controllerType = CONTROLLER_MULTITAP
         elif controllerType.lower() == "four-score" or controllerType.lower() == "f":
            controllerType = CONTROLLER_FOUR_SCORE
         
         for x in range(len(portsList)):         
            if not isConsolePortAvailable(portsList[x],controllerType): # check ALL lanes
               print("ERROR: One or more lanes is in use for port "+str(portsList[x])+"!\n")
               breakout = False
               
         if breakout:
            break
      #8, 16, 24, or 32 bit
      while True:
         controllerBits = int(raw_input("How many bits of data per controller (8, 16, 24, or 32)? "))
         if controllerBits != 8 and controllerBits != 16 and controllerBits != 24 and controllerBits != 32:
            print("ERROR: Bits must be either 8, 16, 24, or 32!\n")
         else:
            break
      #overread value
      while True:
         overread = int(raw_input("Overread value (0 or 1... if unsure choose 0)? "))
         if overread != 0 and overread != 1:
            print("ERROR: Overread be either 0 or 1!\n")
            continue
         else:
            break
      #window mode 0-15.75ms
      while True:
         window = float(raw_input("Window value (0 to disable, otherwise enter time in ms. Must be multiple of 0.25ms. Must be between 0 and 15.75ms)? "))
         if window < 0 or window > 15.25:
            print("ERROR: Window out of range [0, 15.75])!\n")
         elif window%0.25 != 0:
            print("ERROR: Window is not a multiple of 0.25!\n")
         else:
            break
      # dummy frames
      while True:
         try:
            dummyFrames = int(raw_input("Number of blank input frames to prepend? "))
            if window < 0:
               print("ERROR: Please enter a positive number!\n")
               continue
            else:
               break
         except ValueError:
            print("ERROR: Please enter integers!\n")
      #create TASRun object and assign it to our global, defined above
      tasrun = TASRun(numControllers,portsList,controllerType,controllerBits,overread,window,fileName,dummyFrames)
      tasRuns.append(tasrun)
      listenPorts.append(min(tasrun.portsList))
     
      setupCommunication(tasrun)
      if TASLINK_CONNECTED == 1:
         send_frames(len(tasRuns) - 1, prebuffer)

      print("Run is ready to go!")
         
   def do_EOF(self, line):
      """/wave"""
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
      print ("ERROR: the specified interface ("+sys.argv[1]+") is in use")
      sys.exit(0)

#start CLI in its own thread
cli = CLI()
t = threading.Thread(target=cli.cmdloop) # no parens on cmdloop is important... otherwise it blocks
t.start()

# main thread of execution = serial communication thread
# keep loop as tight as possible to eliminate communication overhead
while t.isAlive() and not inputBuffers: # wait until we have at least one run ready to go
   pass

def send_frames(index,amount):
   framecount = frameCounts[index]

   if TASLINK_CONNECTED == 1:
      ser.write(''.join(inputBuffers[index][framecount:(framecount+amount)]))
   else:
      print("DATA SENT: ",''.join(inputBuffers[index][framecount:(framecount+amount)]))
     
   frameCounts[index] += amount
   
#t3h urn

   while True:

      while ser.inWaiting() == 0:
         pass

      c = ser.read()
      
      breakout = False

      for run_index,port in enumerate(listenPorts):
         if port == ord(c)-101:
            send_frames(run_index,1)
            break

t.join() # block wait until CLI thread terminats
if TASLINK_CONNECTED == 1:
   ser.close() # close serial communication cleanly
sys.exit(0) # exit cleanly

# work on 1 run at a time