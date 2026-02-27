<#
.SYNOPSIS
    Uninstall script for the Battery Monitor.
    Removes the shortcut from the Windows Startup folder.
#>

try {
    $WshShell = New-Object -ComObject WScript.Shell
    $StartupDir = $WshShell.SpecialFolders.Item("Startup")
    
    if (-not $StartupDir) {
        throw "Could not find Startup directory."
    }
    
    Write-Host "Startup Directory: $StartupDir"
    $ShortcutPath = Join-Path -Path $StartupDir -ChildPath "BatteryMonitor.lnk"
    
    if (Test-Path -Path $ShortcutPath) {
        Remove-Item -Path $ShortcutPath -Force
        Write-Host "Successfully removed Battery Monitor from Startup."
    }
    else {
        Write-Host "Battery Monitor shortcut not found in Startup. Has it already been uninstalled?"
    }
}
catch {
    Write-Error "Failed to uninstall: $_"
    exit 1
}

Write-Host "Uninstall complete."
Start-Sleep -Seconds 3
