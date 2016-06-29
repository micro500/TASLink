CONTROLLER_NORMAL = 0 # 1 controller
CONTROLLER_Y = 1 #: y-cable [like half a multitap, usually not used by itself]
CONTROLLER_MULTITAP = 2 #: multitap (Ports 1 and 2 only) [snes only]
CONTROLLER_FOUR_SCORE = 3 #: four-score [nes-only peripheral that we don't do anything with]

class TASRun(object):

   customCommand = "Z" # Z is undefined
    
   def __init__(self,num_controllers,ports_list,controller_type,controller_bits,ovr,wndw,file_name):
      self.numControllers = num_controllers
      self.portsList = ports_list
      self.controllerType = controller_type
      self.controllerBits = controller_bits
      self.overread = ovr
      self.window = wndw
      self.inputFile = file_name

      self.fileExtension = file_name.split(".")[-1] # pythonic last elemnt of a list/string/array

      if self.fileExtension == 'r08':
         self.maxControllers = 2
      elif self.fileExtension == 'r16':
         self.maxControllers = 8
      else:
         self.maxControllers = 1 #random default, but truly we need to support other formats
    
   def getInputBuffer(self):
      fh = open(self.inputFile, 'rb')
      buffer = [] # create a new empty buffer
      count = 0
      working_string = ""

      max = int(self.controllerBits/8) * self.numControllers # bytes * number of controllers
      # next we take controller type into account
      if self.controllerType == CONTROLLER_Y or self.controllerType == CONTROLLER_FOUR_SCORE:
         max = max * 2
      elif self.controllerType == CONTROLLER_MULTITAP:
         max = max * 4
         
      while True:
         if count == 0:
            working_string = self.customCommand

         b = fh.read(1) # read one byte

         if len(b) == 0: # fail case
            break

         b = ~ord(b) & 0xFF # flip our 1's and 0's to be hardware compliant; mask just to make sure its a byte
         working_string = working_string + chr(b) # add our byte data
         
         count = count + 1 # note the odd increment timing to make the next check easier
         
         if count == max:
            buffer.append(working_string)
            count = 0
            # now ditch bytes from unused controllers as necessary
            for each in range(1,self.maxControllers-max):
               fh.read(1)

      fh.close()
      
      return buffer
     
     
   def setCustomCommand(self,custom_command):
     self.customCommand = custom_command