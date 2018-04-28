import os
import serial
from serial import SerialException
import sys
import cmd
import threading
import yaml
import gc
import time
# import math

import rlcompleter, readline  # to add support for tab completion of commands
import glob

gc.disable() # for performance reasons

def complete(text, state):
    return (glob.glob(text + '*') + [None])[state]

def complete_nostate(text, *ignored):
    return glob.glob(text + '*') + [None]

readline.set_completer_delims(' \t\n')
readline.parse_and_bind("tab: complete")
readline.set_completer(complete)

# important constants
lanes = [[-1], [1, 2, 5, 6], [3, 4, 7, 8], [5, 6], [7, 8]]
MASKS = 'ABCD'
CONTROLLER_NORMAL = 0  # 1 controller
CONTROLLER_Y = 1  #: y-cable [like half a multitap]
CONTROLLER_MULTITAP = 2  #: multitap (Ports 1 and 2 only) [snes only]
CONTROLLER_FOUR_SCORE = 3  #: four-score [nes-only peripheral that we don't do anything with]
baud = 2000000
prebuffer = 60
ser = None
supportedExtensions = ['r08','r16m'] # TODO: finish implementing this

EVERDRIVEFRAMES = 61 # Number of frames to offset dummy frames by when running on an everdrive

TASLINK_CONNECTED = 1  # set to 0 for development without TASLink plugged in, set to 1 for actual testing

# important global variables to keep track of
consolePorts = [2, 0, 0, 0, 0]  # 1 when in use, 0 when available. 2 is used to waste cell 0
consoleLanes = [2, 0, 0, 0, 0, 0, 0, 0, 0]  # 1 when in use, 0 when available. 2 is used to waste cell 0
masksInUse = [0, 0, 0, 0]
runStatuses = [] # list of currently active runs and their statuses
selected_run = -1

class RunStatus(object):
    tasRun = None
    inputBuffer = None
    customCommand = None
    isRunModified = None
    dpcmState = None
    windowState = None
    frameCount = 0

def readint(question):
    num = -1
    while True:
        ans = raw_input(question)
        try:
            num = int(ans)
        except ValueError:
            print("ERROR: Expected integer, but integer not found")
            continue
        break
    return num

def readfloat(question):
    num = -1
    while True:
        ans = raw_input(question)
        try:
            num = float(ans)
        except ValueError:
            print("ERROR: Expected float, but float not found")
            continue
        break
    return num

def getNextMask():
    for index,letter in enumerate(MASKS):
        if masksInUse[index] == 0:
            masksInUse[index] = 1
            return letter
    return 'Z'

def freeMask(letter):
    val = ord(letter)
    if not (65 <= val <= 68):
        return False
    masksInUse[val-65] = 0
    return True


def load(filename):
    global selected_run

    with open(filename, 'r') as f:
        run = yaml.load(f)
    # check for port conflicts
    if not all(isConsolePortAvailable(port, run.controllerType) for port in run.portsList):
        print("ERROR: Requested ports already in use!")
        return False

    rs = RunStatus()
    rs.customCommand = setupCommunication(run)
    rs.inputBuffer = run.getInputBuffer(rs.customCommand)
    rs.tasRun = run
    rs.isRunModified = False
    rs.dpcmState = run.dpcmFix
    rs.windowState = run.window
    runStatuses.append(rs)

    selected_run = len(runStatuses) - 1

    # add everdrive header if needed
    if run.isEverdrive == True:
        add_everdrive_header(runStatuses[selected_run].tasRun, selected_run)

    send_frames(selected_run, prebuffer)

    print("Run has been successfully loaded!")

def send_frames(index, amount):
    framecount = runStatuses[index].frameCount

    if TASLINK_CONNECTED == 1:
        ser.write(''.join(runStatuses[index].inputBuffer[framecount:(framecount + amount)]))
    else:
        print("DATA SENT: ", ''.join(runStatuses[index].inputBuffer[framecount:(framecount + amount)]))

    runStatuses[index].frameCount += amount

class Transition(object):
    frameno = None
    window = None
    dpcmFix = None

class TASRun(object):
    def __init__(self, num_controllers, ports_list, controller_type, controller_bits, ovr, wndw, file_name, dummy_frames, dpcm_fix, is_everdrive):
        self.numControllers = num_controllers
        self.portsList = ports_list
        self.controllerType = controller_type
        self.controllerBits = controller_bits
        self.overread = ovr
        self.window = wndw
        self.inputFile = file_name
        self.dummyFrames = dummy_frames
        self.dpcmFix = dpcm_fix
        self.transitions = []
        self.isEverdrive = is_everdrive

        self.fileExtension = file_name.split(".")[-1].strip()  # pythonic last element of a list/string/array

        if self.fileExtension == 'r08':
            self.maxControllers = 2
        elif self.fileExtension == 'r16m':
            self.maxControllers = 8
        else:
            self.maxControllers = 1  # random default, but truly we need to support other formats

    def addTransition(self, t):
        self.transitions.append(t)

    def delTransition(self, index):
        del self.transitions[index]

    def getInputBuffer(self, customCommand):
        with open(self.inputFile, 'rb') as myfile:
            wholefile = myfile.read()
        count = 0
        working_string = ""
        numBytes = int(self.controllerBits / 8)
        bytesPerFrame = numBytes * self.maxControllers # 1 * 2 = 2 for NES, 2 * 8 = 16 for SNES
        buffer = [""] * (int(len(wholefile) / bytesPerFrame) + self.dummyFrames)  # create a new empty buffer

        numLanes = self.numControllers
        # next we take controller type into account
        if self.controllerType == CONTROLLER_Y or self.controllerType == CONTROLLER_FOUR_SCORE:
            numLanes *= 2
        elif self.controllerType == CONTROLLER_MULTITAP:
            numLanes *= 4

        bytesPerCommand = numLanes * numBytes

        # add the dummy frames
        for frame in range(self.dummyFrames):
            working_string = customCommand
            for bytes in range(bytesPerCommand):
                working_string += chr(0xFF)
            if self.isEverdrive:
                buffer[EVERDRIVEFRAMES+frame] = working_string
            else:
                buffer[frame] = working_string

        frameno = 0
        invertedfile = [""] * len(wholefile)
        for index, b in enumerate(wholefile):
            invertedfile[index] = chr(~ord(b) & 0xFF)  # flip our 1's and 0's to be hardware compliant; mask just to make sure its a byte

        if self.fileExtension == 'r08':
            while True:
                working_string = customCommand

                one_frame = invertedfile[frameno * 2:frameno * 2 + 2]

                if len(one_frame) != 2:  # fail case
                    break

                working_string += ''.join(one_frame)

                # combine the appropriate parts of working_string
                command_string = working_string[0]
                for counter in range(self.numControllers):
                    if self.controllerType == CONTROLLER_FOUR_SCORE:
                        pass # what is a four score?  would probably require a new file format in fact....
                    else: # normal controller
                        command_string += working_string[counter+1:counter+2]  # math not-so-magic
                buffer[frameno+self.dummyFrames] = command_string
                frameno += 1
        elif self.fileExtension == 'r16m':
            while True:
                working_string = customCommand

                one_frame = invertedfile[frameno*16:frameno*16+16]

                if len(one_frame) != 16:  # fail case
                    break

                working_string += ''.join(one_frame)

                # combine the appropriate parts of working_string
                command_string = working_string[0]
                for counter in range(self.numControllers):
                    if self.controllerType == CONTROLLER_Y:
                        command_string += working_string[(counter * 8) + 1:(counter * 8) + 5]  # math magic
                    elif self.controllerType == CONTROLLER_MULTITAP:
                        command_string += working_string[(counter * 8) + 1:(counter * 8) + 9]  # math magic
                    else:
                        command_string += working_string[(counter * 8) + 1:(counter * 8) + 3]  # math magic
                buffer[frameno+self.dummyFrames] = command_string
                frameno += 1

        return buffer


def setupCommunication(tasrun):
    print("Now preparing TASLink....")
    # claim the ports / lanes
    for port in tasrun.portsList:
        claimConsolePort(port, tasrun.controllerType)

    # begin serial communication
    controllers = list('00000000')
    # set controller lanes and ports
    for port in tasrun.portsList:
        # enable the console ports
        command = "sp"
        command += str(port)  # should look like 'sp1' now
        portData = tasrun.controllerType
        if tasrun.dpcmFix:
            portData += 128 # add the flag for the 8th bit
        if TASLINK_CONNECTED:
            ser.write(command + chr(portData))
        else:
            print(command, portData)

        # enable the controllers lines
        if tasrun.controllerType == CONTROLLER_NORMAL:
            limit = 1
        elif tasrun.controllerType == CONTROLLER_MULTITAP:
            limit = 4
        else:
            limit = 2
        for counter in range(limit):
            command = "sc" + str(lanes[port][counter])  # should look like 'sc1' now
            controllers[8 - lanes[port][counter]] = '1'  # this is used later for the custom stream command
            # now we need to set the byte data accordingly
            byte = list('00000000')
            byte[0] = '1'  # first set it plugged in
            byte[1] = str(tasrun.overread)  # next set overread value
            # set controller size
            if tasrun.controllerBits == 8:
                pass  # both bytes should be 0, so we're good
            elif tasrun.controllerBits == 16:
                byte[7] = '1'
            elif tasrun.controllerBits == 24:
                byte[6] = '1'
            elif tasrun.controllerBits == 32:
                byte[6] = '1'
                byte[7] = '1'
            bytestring = "".join(byte)  # convert binary to string
            if TASLINK_CONNECTED:
                ser.write(command + chr(int(bytestring, 2)))  # send the sc command
            else:
                print(command, bytestring)

    # setup custom stream command
    command = 's'
    customCommand = getNextMask()
    if customCommand == 'Z':
        print("ERROR: all four custom streams are full!")
        # TODO: handle gracefully
    controllerMask = "".join(controllers)  # convert binary to string
    command += customCommand
    if TASLINK_CONNECTED:
        ser.write(command + chr(int(controllerMask, 2)))  # send the sA/sB/sC/sD command
    else:
        print(command, controllerMask)

    # setup events #s e lane_num byte controllerMask
    command = 'se' + str(min(tasrun.portsList))
    # do first byte
    byte = list(
        '{0:08b}'.format(int(tasrun.window / 0.25)))  # create padded bytestring, convert to list for manipulation
    byte[0] = '1'  # enable flag
    bytestring = "".join(byte)  # turn back into string
    if TASLINK_CONNECTED:
        ser.write(command + chr(int(bytestring, 2)) + chr(int(controllerMask, 2)))  # send the sA/sB/sC/sD command
    else:
        print(command, bytestring, controllerMask)

    # finnal, clear lanes and get ready to rock
    if TASLINK_CONNECTED:
        ser.write("r" + chr(int(controllerMask, 2)))
    else:
        print("r", controllerMask)

    return customCommand


def isConsolePortAvailable(port, type):
    # port check
    if consolePorts[port] != 0:  # if port is disabled or in use
        return False

    # lane check
    if type == CONTROLLER_NORMAL:
        if consoleLanes[lanes[port][0]]:
            return False
    elif type == CONTROLLER_MULTITAP:
        if port != 1 and port != 2:  # multitap only works on ports 1 and 2
            return False
        if any(consoleLanes[lanes[port][x]] for x in range(4)):
            return False
    else:  # y-cable or four-score
        if any(consoleLanes[lanes[port][x]] for x in range(2)):
            return False

    return True  # passed all checks


def claimConsolePort(port, type):
    if consolePorts[port] == 0:
        consolePorts[port] = 1  # claim it
        if type == CONTROLLER_NORMAL:
            consoleLanes[lanes[port][0]] = 1
        elif type == CONTROLLER_MULTITAP:
            for lane in lanes[port]:
                consoleLanes[lane] = 1
        else:
            consoleLanes[lanes[port][0]] = 1
            consoleLanes[lanes[port][1]] = 1


def releaseConsolePort(port, type):
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

def remove_everdrive_header(tasRun, runid):
    print("Removing Everdrive Header!\n")
    newbuffer = runStatuses[runid].inputBuffer
    oldbuffer = newbuffer
    newbuffer = oldbuffer[EVERDRIVEFRAMES:]
    runStatuses[runid].inputBuffer = newbuffer

def add_everdrive_header(tasRun, runid):
    print("Adding Everdrive Header!\n")
    newbuffer = runStatuses[runid].inputBuffer
    blankframe = runStatuses[runid].customCommand
    max = int(tasRun.controllerBits / 8) * tasRun.numControllers  # bytes * number of controllers
    # next we take controller type into account
    if tasRun.controllerType == CONTROLLER_Y or tasRun.controllerType == CONTROLLER_FOUR_SCORE:
        max *= 2
    elif tasRun.controllerType == CONTROLLER_MULTITAP:
        max *= 4
    for bytes in range(max):
        blankframe += chr(0xFF)
    startframe = runStatuses[runid].customCommand
    max = int(tasRun.controllerBits / 8) * tasRun.numControllers  # bytes * number of controllers
    # next we take controller type into account
    for bytes in range(max):
        if bytes == 0:
            startframe += chr(0xEF) # press start on controller 1
        else:
            startframe += chr(0xFF)
    newbuffer.insert(0, startframe) # add a frame pressing start to start of input buffer
    for frame in range(0, EVERDRIVEFRAMES-1):
        newbuffer.insert(0, blankframe) # add x number of blank frames to start of input buffer
    runStatuses[runid].inputBuffer = newbuffer

# return false exits the function
# return true exits the whole CLI
class CLI(cmd.Cmd):

    def setprompt(self):
        if selected_run == -1:
            self.prompt = "TASLink> "
        else:
            if runStatuses[selected_run].isRunModified:
                self.prompt = "TASLink[#" + str(selected_run + 1) + "][" + str(
                    runStatuses[selected_run].tasRun.dummyFrames) + "f][UNSAVED]> "
            else:
                self.prompt = "TASLink[#" + str(selected_run + 1) + "][" + str(
                    runStatuses[selected_run].tasRun.dummyFrames) + "f]> "

    def __init__(self):
        cmd.Cmd.__init__(self)

        self.setprompt()

        self.intro = "\nWelcome to the TASLink command-line interface!\nType 'help' for a list of commands.\n"

    def postcmd(self, stop, line):
        self.setprompt()

        return stop

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

    def custom_comp_func(self, text, line, begidx, endidx):
        return self.completenames(text, line, begidx, endidx) + self.completedefault(text, line, begidx, endidx)

    # complete local directory listing
    def completedefault(self, text, *ignored):
        return complete_nostate(text)  # get directory when it doesn't know how to autocomplete

    # do not execute the previous command! (which is the default behavior if not overridden
    def emptyline(self):
        return False

    def do_exit(self, data):
        """Not 'goodbyte' but rather so long for a while"""
        for index,runstatus in enumerate(runStatuses):
            modified = runstatus.isRunModified
            if modified:
                while True:
                    save = raw_input("Run #"+str(index+1)+" is not saved. Save (y/n)? ")
                    if save == 'y':
                        self.do_save(index+1)
                        break
                    elif save == 'n':
                        break
                    else:
                        print("ERROR: Could not interpret response.")

        return True

    def do_save(self, data):
        """Save a run to a file"""
        # print options
        if not runStatuses:
            print("No currently active runs.")
            return False
        if data != "":
            try:
                runID = int(data)
            except ValueError:
                print("ERROR: Invalid run number!")
                return False
            if 0 < runID <= len(runStatuses):  # confirm valid run number
                pass
            else:
                print("ERROR: Invalid run number!")
                return False
        else:
            runID = selected_run + 1

        filename = raw_input("Please enter filename: ")

        with open(filename, 'w') as f:
            f.write(yaml.dump(runStatuses[runID - 1].tasRun))

        runStatuses[runID - 1].isRunModified = False

        print("Save complete!")

    def do_off(self, data):
        """Turns off the SNES via reset pin, if connected"""
        ser.write("sd1")
        print("Console off.")

    def do_on(self, data):
        """Turns on the SNES via reset pin, if connected"""
        ser.write("sd0")
        print("Console on.")

    def do_restart(self, data):
        """Turns the SNES console off, restarts the current run, and turns the SNES console on"""
        self.do_off(data)
        time.sleep(1)
        self.do_reset(data)
        time.sleep(1)
        self.do_on(data)
        print("The restart process is complete!")

    def do_modify_frames(self, data):
        """Modify the initial blank input frames"""
        # print options
        if not runStatuses:
            print("No currently active runs.")
            return False
        if data != "":
            try:
                runID = int(data)
            except ValueError:
                print("ERROR: Invalid run number!")
                pass
            if 0 < runID <= len(runStatuses):  # confirm valid run number
                pass
            else:
                print("ERROR: Invalid run number!")
                return False
        else:
            runID = selected_run + 1
        index = runID - 1
        run = runStatuses[index].tasRun
        print("The current number of initial blank frames is : " + str(run.dummyFrames))
        frames = readint("How many initial blank frames do you want? ")
        difference = frames - run.dummyFrames  # positive means we're adding frames, negative means we're removing frames
        run.dummyFrames = frames
        # modify input buffer accordingly
        if difference > 0:
            working_string = runStatuses[index].customCommand
            max = int(run.controllerBits / 8) * run.numControllers  # bytes * number of controllers
            # next we take controller type into account
            if run.controllerType == CONTROLLER_Y or run.controllerType == CONTROLLER_FOUR_SCORE:
                max *= 2
            elif run.controllerType == CONTROLLER_MULTITAP:
                max *= 4
            for bytes in range(max):
                working_string += chr(0xFF)

            for count in range(difference):
                if run.isEverdrive:
                    runStatuses[index].inputBuffer.insert(EVERDRIVEFRAMES, working_string)
                else:
                    runStatuses[index].inputBuffer.insert(0, working_string)  # add the correct number of blank input frames
        elif difference < 0:  # remove input frames
            if run.isEverdrive:
                runStatuses[index].inputBuffer = runStatuses[index].inputBuffer[0:EVERDRIVEFRAMES]+runStatuses[index].inputBuffer[EVERDRIVEFRAMES-difference:]
            else:
                runStatuses[index].inputBuffer = runStatuses[index].inputBuffer[-difference:]

        runStatuses[index].isRunModified = True

        print("Run has been updated. Remember to save if you want this change to be permanent!")

    def do_reset(self, data):
        """Reset an active run back to frame 0"""
        # print options
        if not runStatuses:
            print("No currently active runs.")
            return False

        if data.lower() == 'all':
            if TASLINK_CONNECTED:
                ser.write("R")
            else:
                print("R")
            for index in range(len(runStatuses)):
                runStatuses[index].frameCount = 0
                send_frames(index, prebuffer)  # re-pre-buffer-!
                # return runs to their original state
                t = Transition()
                t.dpcmFix = runStatuses[index].tasRun.dpcmFix
                t.window = runStatuses[index].tasRun.window
                handleTransition(index,t)
            print("Reset command given to all runs!")
            return False
        elif data != "":
            # confirm integer
            try:
                runID = int(data)
            except ValueError:
                print("ERROR: Please enter 'all' or an integer!\n")
                return False
            if 0 < runID <= len(runStatuses):  # confirm valid run number
                pass
            else:
                print("ERROR: Invalid run number!")
                return False
        else:
            runID = selected_run + 1
        index = runID - 1
        # get the lane mask
        controllers = list('00000000')
        tasrun = runStatuses[index].tasRun
        if tasrun.controllerType == CONTROLLER_NORMAL:
            limit = 1
        elif tasrun.controllerType == CONTROLLER_MULTITAP:
            limit = 4
        else:
            limit = 2

        for port in tasrun.portsList:
            for counter in range(limit):
                controllers[8 - lanes[port][counter]] = '1'

        controllerMask = "".join(controllers)  # convert binary to string

        if TASLINK_CONNECTED:
            ser.write("r" + chr(int(controllerMask, 2)))  # clear the buffer
        else:
            print("r" + controllerMask, 2)  # clear the buffer

        runStatuses[index].frameCount = 0
        send_frames(index, prebuffer)  # re-pre-buffer-!
        # return run to its original state
        t = Transition()
        t.dpcmFix = runStatuses[index].tasRun.dpcmFix
        t.window = runStatuses[index].tasRun.window
        handleTransition(index, t)
        print("Reset complete!")

    def do_remove(self, data):
        """Remove one of the current runs."""
        global selected_run
        # print options
        if not runStatuses:
            print("No currently active runs.")
            return False
        if data != "":
            try:
                runID = int(data)
            except ValueError:
                print("ERROR: Invalid run number!")
                return False
            if 0 < runID <= len(runStatuses):  # confirm valid run number
                pass
            else:
                print("ERROR: Invalid run number!")
                return False
        else:
            runID = selected_run + 1
        index = runID - 1
        # make the mask
        controllers = list('00000000')
        tasrun = runStatuses[index].tasRun
        if tasrun.controllerType == CONTROLLER_NORMAL:
            limit = 1
        elif tasrun.controllerType == CONTROLLER_MULTITAP:
            limit = 4
        else: # y-cable
            limit = 2
        for port in tasrun.portsList:
            for counter in range(limit):
                controllers[8 - lanes[port][counter]] = '1'
        controllerMask = "".join(controllers)  # convert binary to string
        # free ports
        for port in runStatuses[index].tasRun.portsList:
            releaseConsolePort(port, runStatuses[index].tasRun.controllerType)
        # free custom stream and event
        freeMask(runStatuses[index].customCommand)
        # remove input and run from lists
        del runStatuses[index]

       # clear the lanes
        if TASLINK_CONNECTED:
            ser.write("r" + chr(int(controllerMask, 2)))  # clear the buffer
        else:
            print("r" + controllerMask, 2)  # clear the buffer

        selected_run = len(runStatuses) - 1 # even if there was only 1 run, it will go to -1, signaling we have no more runs

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
        load(filename)

    def do_list(self, data):
        """List all active runs"""
        if not runStatuses:
            print("No currently active runs.")
            return False
        for index, runstatus in enumerate(runStatuses):
            print("Run #" + str(index + 1) + ": ")
            print yaml.dump(runstatus.tasRun)
        pass

    def do_select(self, data):
        """Select a run to modify with other commands"""
        global selected_run

        if not runStatuses:
            print("No currently active runs.")
            return False

        if data != "":
            # confirm integer
            try:
                runID = int(data)
            except ValueError:
                print("ERROR: Please enter an integer!\n")
                return False
            if 0 < runID <= len(runStatuses):  # confirm valid run number
                pass
            else:
                print("ERROR: Invalid run number!")
                return False
        else:
            while True:
                runID = readint("Which run # do you want to select? ")
                if 0 < runID <= len(runStatuses):  # confirm valid run number
                    break
                else:
                    print("ERROR: Invalid run number!")
        selected_run = runID - 1

    def do_add_transition(self, data):
        """Adds a transition of communication settings at a particular frame"""
        if selected_run == -1:
            print("ERROR: No run is selected!\n")
            return
        # transitions
        while True:
            try:
                frameNum = readint("At what frame will this transition occur? ")
                if frameNum <= 0:
                    print("ERROR: Please enter a positive number!\n")
                    continue
                else:
                    break
            except ValueError:
                print("ERROR: Please enter an integer!\n")
        # DPCM fix
        while True:
            dpcm_fix = raw_input("Apply DPCM fix (y/n)? ")
            if dpcm_fix.lower() == 'y':
                dpcm_fix = True
                break
            elif dpcm_fix.lower() == 'n':
                dpcm_fix = False
                break
            print("ERROR: Please enter y for yes or n for no!\n")
        # window mode 0-15.75ms
        while True:
            window = readfloat(
                "Window value (0 to disable, otherwise enter time in ms. Must be multiple of 0.25ms. Must be between 0 and 15.75ms)? ")
            if window < 0 or window > 15.25:
                print("ERROR: Window out of range [0, 15.75])!\n")
            elif window % 0.25 != 0:
                print("ERROR: Window is not a multiple of 0.25!\n")
            else:
                break
        t = Transition()
        t.dpcmFix = dpcm_fix
        t.frameno = frameNum
        t.window = window
        runStatuses[selected_run].tasRun.addTransition(t)
        runStatuses[selected_run].isRunModified = True
        
    def do_toggle_everdrive(self, data):
        if selected_run == -1:
            print("ERROR: No run is selected!\n")
            return
        if runStatuses[selected_run].tasRun.isEverdrive == True:
            remove_everdrive_header(runStatuses[selected_run].tasRun, selected_run)
            runStatuses[selected_run].tasRun.isEverdrive = False
        elif runStatuses[selected_run].tasRun.isEverdrive == False:
            add_everdrive_header(runStatuses[selected_run].tasRun, selected_run)
            runStatuses[selected_run].tasRun.isEverdrive = True

    def do_new(self, data):
        """Create a new run with parameters specified in the terminal"""
        global selected_run
        # get input file
        while True:
            fileName = raw_input("What is the input file (path to filename) ? ")
            if not os.path.isfile(fileName):
                sys.stderr.write('ERROR: File does not exist!\n')
            else:
                break
        # get ports to use
        while True:
            try:
                breakout = True
                portsList = raw_input("Which physical controller port numbers will you use (1-4, commas between port numbers)? ")
                portsList = map(int, portsList.split(","))  # splits by commas or spaces, then convert to int
                numControllers = len(portsList)
                for port in portsList:
                    if port not in range(1, 5):  # Top of range is exclusive
                        print("ERROR: Port out of range... " + str(port) + " is not between (1-4)!\n")
                        breakout = False
                        break
                    if not isConsolePortAvailable(port, CONTROLLER_NORMAL):  # check assuming one lane at first
                        print("ERROR: The main data lane for port " + str(port) + " is already in use!\n")
                        breakout = False
                        break
                if any(portsList.count(x) > 1 for x in portsList):  # check duplciates
                    print("ERROR: One of the ports was listed more than once!\n")
                    continue
                if breakout:
                    break
            except ValueError:
                print("ERROR: Please enter integers!\n")
        # get controller type
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
                if not isConsolePortAvailable(portsList[x], controllerType):  # check ALL lanes
                    print("ERROR: One or more lanes is in use for port " + str(portsList[x]) + "!\n")
                    breakout = False

            if breakout:
                break
        # 8, 16, 24, or 32 bit
        while True:
            controllerBits = readint("How many bits of data per controller (8, 16, 24, or 32)? ")
            if controllerBits != 8 and controllerBits != 16 and controllerBits != 24 and controllerBits != 32:
                print("ERROR: Bits must be either 8, 16, 24, or 32!\n")
            else:
                break
        # overread value
        while True:
            overread = readint("Overread value (0 or 1... if unsure choose 0)? ")
            if overread != 0 and overread != 1:
                print("ERROR: Overread be either 0 or 1!\n")
                continue
            else:
                break
        # DPCM fix
        while True:
            dpcm_fix = raw_input("Apply DPCM fix (y/n)? ")
            if dpcm_fix.lower() == 'y':
                dpcm_fix = True
                break
            elif dpcm_fix.lower() == 'n':
                dpcm_fix = False
                break
            print("ERROR: Please enter y for yes or n for no!\n")
        # window mode 0-15.75ms
        while True:
            window = readfloat("Window value (0 to disable, otherwise enter time in ms. Must be multiple of 0.25ms. Must be between 0 and 15.75ms)? ")
            if window < 0 or window > 15.25:
                print("ERROR: Window out of range [0, 15.75])!\n")
            elif window % 0.25 != 0:
                print("ERROR: Window is not a multiple of 0.25!\n")
            else:
                break
        # dummy frames
        while True:
            try:
                dummyFrames = readint("Number of blank input frames to prepend? ")
                if dummyFrames < 0:
                    print("ERROR: Please enter a positive number!\n")
                    continue
                else:
                    break
            except ValueError:
                print("ERROR: Please enter integers!\n")
        # is the run on a everdrive
        while True:
            is_everdrive = raw_input("Does the input file have a header for playback on an Everdrive (y/n)? ")
            if is_everdrive.lower() == 'y':
                is_everdrive = True
                break
            elif is_everdrive.lower() == 'n':
                is_everdrive = False
                break
            print("ERROR: Please enter y for yes or n for no!\n")
        # create TASRun object and assign it to our global, defined above
        tasrun = TASRun(numControllers, portsList, controllerType, controllerBits, overread, window, fileName, dummyFrames, dpcm_fix, is_everdrive)

        rs = RunStatus()
        rs.customCommand = setupCommunication(tasrun)
        rs.inputBuffer = tasrun.getInputBuffer(rs.customCommand)
        rs.tasRun = tasrun
        rs.isRunModified = True
        rs.dpcmState = dpcm_fix
        rs.windowState = window
        runStatuses.append(rs)

        selected_run = len(runStatuses) - 1

        # add everdrive header if needed
        if tasrun.isEverdrive == True:
            add_everdrive_header(runStatuses[selected_run].tasRun, selected_run)

        send_frames(selected_run, prebuffer)

        print("Run is ready to go!")

    def do_EOF(self, line):
        """/wave"""
        return True

    def postloop(self):
        print

def handleTransition(run_index, transition):
    if runStatuses[run_index].dpcmState != transition.dpcmFix:
        for port in runStatuses[run_index].tasRun.portsList:
            # enable the console ports
            command = "sp"
            command += str(port)  # should look like 'sp1' now
            portData = runStatuses[run_index].tasRun.controllerType
            if transition.dpcmFix:
                portData += 128  # add the flag for the 8th bit
            ser.write(command + chr(portData))
            runStatuses[run_index].dpcmState = transition.dpcmFix
    if runStatuses[run_index].windowState != transition.window:
        controllers = list('00000000')
        for port in runStatuses[run_index].tasRun.portsList:
            if runStatuses[run_index].tasRun.controllerType == CONTROLLER_NORMAL:
                limit = 1
            elif runStatuses[run_index].tasRun.controllerType == CONTROLLER_MULTITAP:
                limit = 4
            else:
                limit = 2
            for counter in range(limit):
                controllers[8 - lanes[port][counter]] = '1'  # this is used later for the custom stream command
        controllerMask = "".join(controllers)  # convert binary to string

        # setup events #s e lane_num byte controllerMask
        command = 'se' + str(min(runStatuses[run_index].tasRun.portsList))
        # do first byte
        byte = list('{0:08b}'.format(
            int(transition.window / 0.25)))  # create padded bytestring, convert to list for manipulation
        byte[0] = '1'  # enable flag
        bytestring = "".join(byte)  # turn back into string
        ser.write(command + chr(int(bytestring, 2)) + chr(int(controllerMask, 2)))
        runStatuses[run_index].windowState = transition.window

# ----- MAIN EXECUTION BEGINS HERE -----

if len(sys.argv) < 2:
    sys.stderr.write('Usage: ' + sys.argv[0] + ' <interface>\n\n')
    sys.stderr.write('OR: ' + sys.argv[0] + ' <interface> <file1> <file2> ... \n\n')
    sys.exit(0)

if TASLINK_CONNECTED:
    try:
        ser = serial.Serial(sys.argv[1], baud, timeout=1)
    except SerialException:
        print ("ERROR: the specified interface (" + sys.argv[1] + ") is in use")
        sys.exit(0)

    # ensure we start with all events disabled
    for x in range(1,5):
        ser.write("se"+str(x)+chr(0)+chr(0))

if len(sys.argv) > 2:  # load some initial files!
    for filename in sys.argv[2:]:
        if not os.path.isfile(filename):
            print("ERROR: File "+filename+" does not exist!")
            continue
        load(filename)

# start CLI in its own thread
cli = CLI()
t = threading.Thread(target=cli.cmdloop)  # no parens on cmdloop is important... otherwise it blocks
t.start()

# main thread of execution = serial communication thread
# keep loop as tight as possible to eliminate communication overhead
while t.isAlive() and not runStatuses:  # wait until we have at least one run ready to go
    time.sleep(0.1)
    pass

if TASLINK_CONNECTED and not t.isAlive():
    ser.close()
    sys.exit(0)

# t3h urn
if TASLINK_CONNECTED:
    while t.isAlive():
        if not t.isAlive():
            ser.close() # close serial communication cleanly
            break

        c = ser.read(1)
        if c == '': # nothing was waiting
            continue # so try again
        numBytes = ser.inWaiting() # is anything else waiting
        if numBytes > 0:
            c += ser.read(numBytes)
            if numBytes > 60:
                print ("WARNING: High frame read detected: " + str(numBytes))
        latchCounts = [-1, c.count('f'), c.count('g'), c.count('h'), c.count('i')]

        for run_index, runstatus in enumerate(runStatuses):
            run = runstatus.tasRun
            port = min(run.portsList) # the same port we have an event listener on
            latches = latchCounts[port]

            for transition in run.transitions:
                if 0 <= (transition.frameno+run.dummyFrames+prebuffer) - runstatus.frameCount < latches: # we're about to pass the transition frame
                    handleTransition(run_index,transition)

            if latches > 0:
                send_frames(run_index, latches)
