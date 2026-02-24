<#
.SYNOPSIS
    Monitors battery percentage and status, notifying the user when to plug/unplug.
.DESCRIPTION
    Runs in a loop every 60 seconds.
    Notifies when:
    - Battery > 80% and Plugged In (Status = 2)
    - Battery < 20% and Unplugged (Status = 1)
.NOTES
    Author: Antigravity
    Date: 2026-02-19
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create notification object
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -Id $pid).Path)
$notify.Visible = $True

Function Send-Notification {
    param (
        [string]$Title,
        [string]$Message,
        [string]$IconType = "Info" # Info, Warning, Error, None
    )
    $notify.BalloonTipTitle = $Title
    $notify.BalloonTipText = $Message
    $notify.BalloonTipIcon = $IconType
    $notify.ShowBalloonTip(10000)
    
    # Text-to-Speech
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.SpeakAsync($Message)
}

Write-Host "Battery Monitor Started..."
Send-Notification -Title "Battery Monitor" -Message "Monitoring started."

# State tracking to avoid spamming (only notify once per state change/threshold crossing)
$lastNotification = ""

while ($true) {
    try {
        $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop
        
        # BatteryStatus: 1 = Discharging, 2 = AC Power (Charging or Fully Charged if 100%)
        # EstimatedChargeRemaining: 0-100
        $percent = $battery.EstimatedChargeRemaining
        $status = $battery.BatteryStatus
        
        # Debug output (optional, visible if run in console)
        # Write-Host "Battery: $percent%, Status: $status"

        if ($percent -ge 80 -and $status -eq 2) {
            # High Battery & Plugged In -> Unplug
            if ($lastNotification -ne "High") {
                Send-Notification -Title "Battery High ($percent%)" -Message "Unplug your charger to protect battery health." -IconType "Warning"
                $lastNotification = "High"
            }
        }
        elseif ($percent -le 20 -and $status -eq 1) {
            # Low Battery & Unplugged -> Plug In
            if ($lastNotification -ne "Low") {
                Send-Notification -Title "Battery Low ($percent%)" -Message "Plug in your charger!" -IconType "Warning"
                $lastNotification = "Low"
            }
        }
        else {
            # Reset notification state if we are in the "safe" zone (21-79%)
            # or if the user complied (e.g. was High, now Unplugged)
            
            # Simple logic: If we are not in a condition that triggers a notification, 
            # we can potentially reset.
            # However, we want to avoid spamming if it oscillates between 79 and 80.
            # Let's reset only if we are significantly away or status changed.
            
            if ($percent -lt 78 -and $percent -gt 22) {
                $lastNotification = ""
            }
            
            # If we were "High" (plugged in), and now we are unplugged (status 1), reset
            if ($lastNotification -eq "High" -and $status -eq 1) {
                $lastNotification = ""
            }
            # If we were "Low" (unplugged), and now we are plugged in (status 2), reset
            if ($lastNotification -eq "Low" -and $status -eq 2) {
                $lastNotification = ""
            }
        }
    }
    catch {
        Write-Error "Failed to get battery status: $_"
    }

    Start-Sleep -Seconds 60
}
