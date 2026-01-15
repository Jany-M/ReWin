REM Launch ReWin Restore GUI silently without console window
Set objShell = CreateObject("WScript.Shell")
strPath = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
objShell.Run "pythonw.exe """ & strPath & "\src\gui\restore_gui.py""", 0, False
