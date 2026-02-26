Set WshShell = CreateObject("WScript.Shell") 
' 0 means hide window, false means don't wait for completion
Dim scriptDir
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "\battery_monitor.ps1""", 0, False
