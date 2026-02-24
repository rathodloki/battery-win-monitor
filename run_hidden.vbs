Set WshShell = CreateObject("WScript.Shell") 
' 0 means hide window, false means don't wait for completion
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Users\ratho\.gemini\antigravity\playground\ultraviolet-nova\battery_monitor.ps1""", 0, False
