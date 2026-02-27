<#
.SYNOPSIS
    Monitors battery percentage and status, notifying the user when to plug/unplug.
    Includes smart idle detection to avoid alerting when the user is away, 
    and a gentle reminder system if the alert is ignored.
.DESCRIPTION
    Runs in a loop every 60 seconds.
    Notifies when:
    - Battery >= 80% and Plugged In  -> Unplug
    - Battery <= 20% and Unplugged   -> Plug in
    Uses: banner_popup.ps1 (separate process), TTS speech.
.NOTES
    Author: Antigravity
    Date: 2026-02-25
#>
$ErrorActionPreference = "Continue"

try { Add-Type -AssemblyName System.Speech } catch {}

# ── C# User Activity Detection ────────────────────────────────────────────────
$UserActivityCode = @'
using System;
using System.Runtime.InteropServices;

public class UserActivity {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("User32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static uint GetIdleSeconds() {
        LASTINPUTINFO lastInPut = new LASTINPUTINFO();
        lastInPut.cbSize = (uint)Marshal.SizeOf(lastInPut);
        if (GetLastInputInfo(ref lastInPut)) {
            // Environment.TickCount is uptime in milliseconds. 
            // dwTime is the tick count of the last input.
            return ((uint)Environment.TickCount - lastInPut.dwTime) / 1000;
        }
        return 0;
    }
}
'@
Add-Type -TypeDefinition $UserActivityCode -Language CSharp

function Get-UserIdleTime {
    return [UserActivity]::GetIdleSeconds()
}

# ── Resolve the directory this script lives in (works in all launch modes) ───
$scriptDir = if ($PSScriptRoot -and $PSScriptRoot -ne '') {
    $PSScriptRoot
}
elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    $PWD.Path
}
$bannerFile = Join-Path $scriptDir "banner_popup.ps1"


# ── Show-BatteryBanner ────────────────────────────────────────────────────────
function Show-BatteryBanner {
    param([string]$Title, [string]$Message, [string]$Level = "Low")
    try {
        $bf = $script:bannerFile -replace "'", "''"
        $t = $Title -replace "'", "''"
        $m = $Message -replace "'", "''"
        $cmd = "& '$bf' -Title '$t' -Message '$m' -Level '$Level'"
        $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $enc" `
            -WindowStyle Hidden -ErrorAction Stop
    }
    catch {
        Write-Host "  [Banner] Warning: could not show banner: $_"
    }
}

# ── Send-Alert ────────────────────────────────────────────────────────────────
function Send-Alert {
    param([string]$Title, [string]$Message, [string]$Level = "Low")

    # 1) Popup banner (separate process, non-blocking)
    Show-BatteryBanner -Title $Title -Message $Message -Level $Level

    # 3) Text-to-Speech
    try {
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        try { $synth.SelectVoice("Microsoft Zira Desktop") } catch {}
        $synth.Speak($Message) | Out-Null
        $synth.Dispose()
    }
    catch {}
}

# ── Configuration Variables ───────────────────────────────────────────────────
$nagIntervalMinutes = 3
$idleThresholdSeconds = 120 # Considers the user "away" if idle for 2 minutes
$lastNotification = ""
$lastNotificationTime = [DateTime]::MinValue

Write-Host "Battery Monitor Started... (Ctrl+C to stop)"
Write-Host "  Banner file: $bannerFile"

# Startup notification
Send-Alert -Title "Battery Monitor" -Message "Battery monitoring has started." -Level "High"

# ── Main Monitor Loop ─────────────────────────────────────────────────────────
while ($true) {
    try {
        $batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
        
        # Average out the remaining charge across all batteries
        $percent = [Math]::Round(($batteries | Measure-Object -Property EstimatedChargeRemaining -Average).Average)
        
        # Determine if it's plugged in (1 = Discharging. Anything else = Plugged In/Charging)
        $isPluggedIn = ($batteries[0].BatteryStatus -ne 1)

        # Check how long the user has been idle
        $idleSeconds = Get-UserIdleTime
        
        Write-Host "$(Get-Date -Format 'HH:mm:ss')  Battery: $percent%  Plugged In: $isPluggedIn  Idle: $idleSeconds sec"

        # Boolean flags to make the logic readable
        $isUserActive = $idleSeconds -lt $idleThresholdSeconds
        $timeSinceLastAlert = (Get-Date) - $lastNotificationTime

        # ── HIGH BATTERY (>= 80% & Plugged In) ──
        if ($percent -ge 80 -and $isPluggedIn) {
            # Alert if we haven't sent one yet, OR if 5 minutes have passed
            $needsAlert = ($lastNotification -ne "High") -or ($timeSinceLastAlert.TotalMinutes -ge $nagIntervalMinutes)
            
            if ($needsAlert -and $isUserActive) {
                Send-Alert `
                    -Title   "Battery High ($percent%)" `
                    -Message "Unplug your charger to protect battery health." `
                    -Level   "High"
                
                $lastNotification = "High"
                $lastNotificationTime = Get-Date
            }
            elseif ($needsAlert -and -not $isUserActive) {
                Write-Host "  [Status] Battery high, but user is away. Waiting for return..."
            }
        }
        
        # ── LOW BATTERY (<= 20% & Unplugged) ──
        elseif ($percent -le 20 -and -not $isPluggedIn) {
            $needsAlert = ($lastNotification -ne "Low") -or ($timeSinceLastAlert.TotalMinutes -ge $nagIntervalMinutes)
            
            if ($needsAlert -and $isUserActive) {
                Send-Alert `
                    -Title   "Battery Low ($percent%)" `
                    -Message "Battery low. Plug in your charger now to protect battery health." `
                    -Level   "Low"
                
                $lastNotification = "Low"
                $lastNotificationTime = Get-Date
            }
            elseif ($needsAlert -and -not $isUserActive) {
                Write-Host "  [Status] Battery low, but user is away. Waiting for return..."
            }
        }
        
        # ── RESET STATE ──
        else {
            # If battery is in the safe zone, or the user fixed the issue, reset the tracker
            if ($percent -gt 22 -and $percent -lt 78) { $lastNotification = "" }
            if ($lastNotification -eq "High" -and -not $isPluggedIn) { $lastNotification = "" }
            if ($lastNotification -eq "Low" -and $isPluggedIn) { $lastNotification = "" }
        }
    }
    catch {
        Write-Host "$(Get-Date -Format 'HH:mm:ss')  Could not read battery: $_"
    }

    Start-Sleep -Seconds 60
}