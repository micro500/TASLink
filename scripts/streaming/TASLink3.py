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
def get_input(type, prompt, default=''):
    while True:
        try:
            data = input(prompt)
            if data == default == None:
                print('No Default Configured')
                continue
            if data == '' and default != '':
                return default
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
                if data.lower() in (1,'true','y','yes')
                    return True
                elif data.lower() in (0,'false','n','no')
        except EOFError:
            print('EOF')
            return None

    ### MAIN LOOP ###
    signal.signal(signal.SIGINT,signal.SIG_IGN) # Catch Ctrl+C from interupting the mainloop
