#!/usr/bin/env python3
# ImportModules
import os
import sys
import cmd
import threading
import yaml
import gc
import time
import rlcompleter
import readline
import glob
import signal # Handle InteruptSignals
import serial
from serial import SerialException

# GarbageCollection
gc.disable() # for performance reasons

# Readline Config
def complete(text, state):
    return (glob.glob(text + '*') + [None])[state]
def complete_nostate(text, *ignored):
    return glob.glob(text + '*') + [None]
readline.set_completer_delims(' \t\n')
readline.parse_and_bind("tab: complete")
readline.set_completer(complete)

# Set Constants
lanes = [[-1], [1, 2, 5, 6], [3, 4, 7, 8], [5, 6], [7, 8]]
MASKS = 'ABCD'
CONTROLLER_NORMAL = 0  # 1 controller
CONTROLLER_Y = 1  #: y-cable [like half a multitap]
CONTROLLER_MULTITAP = 2  #: multitap (Ports 1 and 2 only) [snes only]
CONTROLLER_FOUR_SCORE = 3  #: four-score [nes-only peripheral that we don't do anything with]
baud = 2000000
prebuffer = 60
ser = None
EVERDRIVEFRAMES = 61 # Number of frames to offset dummy frames by when running on an everdrive
SD2SNESFRAMES = 130 # Number of frames to offset dummy frames by when running on a SD2SNES
# important global variables to keep track of
consolePorts = [2, 0, 0, 0, 0]  # 1 when in use, 0 when available. 2 is used to waste cell 0
consoleLanes = [2, 0, 0, 0, 0, 0, 0, 0, 0]  # 1 when in use, 0 when available. 2 is used to waste cell 0
masksInUse = [0, 0, 0, 0]
runStatuses = [] # list of currently active runs and their statuses
selected_run = -1
TASLINK_CONNECTED = 1  # set to 0 for development without TASLink plugged in, set to 1 for actual testing
supportedExtensions = ['r08','r16m'] # TODO: finish implementing this
# Default Options for new runs
DEFAULTS = {'contype': "normal",
            'overread': 0,
            'dpcmfix': "n",
            'windowmode': 0,
            'dummyframes': 0}

class RunStatus(object):
    tasRun = None
    inputBuffer = None
    customCommand = None
    isRunModified = None
    dpcmState = None
    windowState = None
    frameCount = 0
    defaultSave = None
    isLoadedRun = False

# types implemented int,str,float,bool
# constraints only work on int and float
def get_input(type, prompt, default='', constraints={}):
    while True:
        try:
            data = input(prompt)
            if data == default == None:
                print('ERROR: No Default Configured')
                continue
            if data == '' and default != '':
                return default
            if 'min' in constraints:
                if data < constraints['min']:
                    print('ERROR: Input less than Minimium of ' + str(constraints['min']))
                    continue
            if 'max' in constraints:
                if data > constraints['max']:
                    print('ERROR: Input greater than maximum of ' + str(constraints['max']))
                    continue
            if 'interval' in constraints:
                if data % constraints['interval'] != 0:
                    print('ERROR: Input does not match interval of ' + str(constraints['max']))
                    continue
            if type == 'int':
                try:
                    return int(data)
                except ValueError:
                    print('ERROR: Expected integer')
            if type == 'float':
                try:
                    return float(data)
                except ValueError:
                    print('ERROR: Expected float')
            if type == 'str':
                try:
                    return str(data)
                except ValueError:
                    print('ERROR: Expected string')
            if type == 'bool':
                if data.lower() in (1,'true','y','yes'):
                    return True
                elif data.lower() in (0,'false','n','no'):
                    return False
                else:
                    print('ERROR: Expected boolean')
        except EOFError:
            print('EOF')
            return None

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

def load(filename, batch=False):
    global selected_run
    with open(filename, 'r') as f:
        loadedrun = yaml.load(f)
    # check for missing values from run
    missingValues = 0
    try:
        numControllers = loadedrun.numControllers
        portsList = loadedrun.portsList
        controllerType = loadedrun.controllerType
        controllerBits = loadedrun.controllerBits
        inputFile = loadedrun.inputFile
    except AttributeError as error:
            print("ERROR: Missing Attribute from loaded run!")
            print(error)
            return False
    try:
        overread = loadedrun.overread
    except AttributeError:
        missingValues += 1
        overread = get_input(type = 'int',
            prompt = 'Overread value (0 or 1) [def=' + str(DEFAULTS['overread']) + ']? ',
            default = DEFAULTS['overread'],
            constraints = {'min': 0, 'max': 1})
        if overread == None:
            return False
    try:
        window = loadedrun.window
    except AttributeError as error:
        missingValues += 1
        window = get_input(type = 'float',
            prompt = 'Window value (0 to disable, otherwise enter time in ms. Must be multiple of 0.25ms. Must be between 0 and 15.75ms) [def=' + str(DEFAULTS['windowmode']) + ']? ',
            default = DEFAULTS['windowmode'],
            constraints = {'min': 0, 'max': 15.75, 'interval': 0.25})
        
        
        
        
### MAIN LOOP ###
# signal.signal(signal.SIGINT,signal.SIG_IGN) # Catch Ctrl+C from interupting the mainloop
