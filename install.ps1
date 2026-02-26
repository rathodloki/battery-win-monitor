try {
    $WshShell = New-Object -ComObject WScript.Shell
    $StartupDir = $WshShell.SpecialFolders.Item("Startup")
    if (-not $StartupDir) {
        throw "Could not find Startup directory."
    }
    Write-Host "Startup Directory: $StartupDir"

    $ShortcutPath = Join-Path -Path $StartupDir -ChildPath "BatteryMonitor.lnk"
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $Target = Join-Path $ScriptDir "run_hidden.vbs"

    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $Target
    $Shortcut.IconLocation = "C:\Windows\System32\powercpl.dll,0"
    $Shortcut.Description = "Battery Monitor Background Service"
    $Shortcut.Save()

    Write-Host "Shortcut created successfully at: $ShortcutPath"
}
catch {
    Write-Error "Failed to install shortcut: $_"
    exit 1
}
