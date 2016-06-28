import wx
import yaml
import os

DefaultFileName = "tasbot.yml"


class TasbotUIFrame(wx.Frame):
   def __init__(self, parent=None, id=wx.ID_ANY, title="TASbot UI"):
      wx.Frame.__init__(self, parent, id, title)
      
      self.optionData = None
      
      filemenu = wx.Menu()
      menuOpen = filemenu.Append(-1, "&Open", "Open a file")
      menuSave = filemenu.Append(-1, "&Save as...", "Save to file")
      menuExit = filemenu.Append(wx.ID_EXIT, "E&xit", "Terminate the program")
      
      menuBar = wx.MenuBar()
      menuBar.Append(filemenu, "&File")
      self.SetMenuBar(menuBar)
      
      self.Bind(wx.EVT_MENU, self.onOpen, menuOpen)
      self.Bind(wx.EVT_MENU, self.onSave, menuSave)
      self.Bind(wx.EVT_MENU, self.onExit, menuExit)
      
      self.mainPanel = wx.Panel(self)
      self.optionPanel = wx.Panel(self.mainPanel, style=wx.BORDER_SUNKEN)
      
      self.goButton = wx.Button(self.mainPanel, label="Go, TASbot!")
      self.goButton.Disable()
      self.goButton.Bind(wx.EVT_BUTTON, self.onGoButton)
      
      self.optionSizer = wx.BoxSizer(wx.VERTICAL)
      self.optionSizer.Add(
         wx.StaticText(self.optionPanel, label="Load a file"),
         1, wx.ALL|wx.ALIGN_CENTER
      )
      self.optionPanel.SetSizer(self.optionSizer)
      
      if os.path.isfile(DefaultFileName):
         self.loadFile(DefaultFileName)
      
      self.mainSizer = wx.BoxSizer(wx.VERTICAL)
      self.mainSizer.Add(self.optionPanel, 1, wx.ALL|wx.EXPAND, 5)
      self.mainSizer.Add(self.goButton, 0, wx.LEFT|wx.RIGHT|wx.BOTTOM|wx.ALIGN_CENTER_HORIZONTAL, 5)
      self.mainPanel.SetSizer(self.mainSizer)
      
      fitSize = self.mainSizer.Fit(self.mainPanel)
      currentSize = self.Size
      fitSize.x += 20
      fitSize.y += 20
      if fitSize.x > currentSize.x or fitSize.y > currentSize.y:
         self.SetSize((max(fitSize.x, currentSize.x), max(fitSize.y, currentSize.y)))
      
   def onOpen(self, event):
      dlg = wx.FileDialog(
         self, 
         message="Choose a file", 
         defaultDir=os.getcwd(),
         wildcard="*.yml",
         style=wx.FD_OPEN|wx.FD_FILE_MUST_EXIST
      )
      if dlg.ShowModal() != wx.ID_OK:
         return
         
      path = dlg.GetPath()
      dlg.Destroy()
      self.loadFile(path)
      
   def onSave(self, event):
      if self.optionData is None:
         dlg = wx.MessageDialog(
            self,
            "Invalid operation",
            "Cannot save because no options are loaded",
            style=wx.OK|wx.ICON_INFORMATION
         )
         dlg.ShowModal()
         dlg.Destroy()
         return
      
      self.readWidgets()
      
      dlg = wx.FileDialog(
         self,
         message="Choose a location to save",
         defaultDir=os.getcwd(),
         defaultFile=DefaultFileName,
         wildcard="*.yml",
         style=wx.FD_SAVE
      )
      if dlg.ShowModal() != wx.ID_OK:
         return
         
      path = dlg.GetPath()
      dlg.Destroy()
      
      if os.path.isfile(path):
         os.remove(path)
      with open(path, mode='w') as fh:
         yaml.safe_dump(self.optionData, fh, default_flow_style=False)

   def onExit(self, event):
      self.Close(True)
      
   def onGoButton(self, event):
      self.readWidgets()
      print "Go, TASbot!"
      # This is when streaming would start. All the option data is available in self.optionData
      
   def loadFile(self, filename):
      print "Loading %s" % (filename,)
      with open(filename) as fh:
         newData = yaml.safe_load(fh)
      
      # First a quick sanity check
      if not isinstance(newData, list) or \
            len(newData) < 1 or \
            not isinstance(newData[0], dict):
         
         dlg = wx.MessageDialog(
            self,
            "Invalid data",
            "The data in that file is invalid",
            style=wx.OK|wx.ICON_ERROR
         )
         dlg.ShowModal()
         dlg.Destroy()
         return
         
      self.goButton.Enable()
      self.optionData = newData
      self.optionWidgets = [{} for d in self.optionData]
      self.optionSizer.Clear(True)
      self.optionSizer = wx.FlexGridSizer(rows=3, cols=1+len(self.optionData), vgap=0, hgap=0)
      for k in self.optionData[0].keys():
         self.optionSizer.Add(wx.StaticText(self.optionPanel, label=k), 0, wx.ALL|wx.ALIGN_RIGHT, 5)
         for i in xrange(len(self.optionData)):
            itemData = self.optionData[i]
            value = itemData[k]
            if isinstance(value, bool):
               # boolean, make a checkbox
               checkbox = wx.CheckBox(self.optionPanel, label="")
               checkbox.SetValue(value)
               self.optionWidgets[i][k] = checkbox
               self.optionSizer.Add(checkbox, 1, wx.ALL|wx.ALIGN_LEFT, 5)
            #elif isinstance(value, basestring):
               #string
            else:
               # number or anything else
               entry = wx.TextCtrl(self.optionPanel, size=(120, -1))
               entry.SetValue(str(value))
               self.optionWidgets[i][k] = entry
               self.optionSizer.Add(entry, 1, wx.ALL|wx.ALIGN_LEFT, 5)
      for i in xrange(len(self.optionData)):
         self.optionSizer.AddGrowableCol(i+1)
               
      self.optionPanel.SetSizerAndFit(self.optionSizer)
      
      if hasattr(self, "mainSizer"):
         self.mainSizer.Layout()
      
   def readWidgets(self):
      # Read all the widgets and set the option data accordingly
      for i in xrange(len(self.optionData)):
         for k in self.optionData[0]:
            self.optionData[i][k] = self.optionWidgets[i][k].GetValue()

      
def main():
   app = wx.App(False)
   frame = TasbotUIFrame()
   frame.Show(True)
   app.MainLoop()
   

if __name__ == "__main__":
   main()