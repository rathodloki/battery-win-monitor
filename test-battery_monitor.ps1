<#
.SYNOPSIS
    Test script for battery_monitor banners (uses banner_popup.ps1).
.USAGE
    .\test-battery_monitor.ps1              # shows both banners (Low then High)
    .\test-battery_monitor.ps1 -Test Low    # only the LOW banner
    .\test-battery_monitor.ps1 -Test High   # only the HIGH banner
#>

param(
    [ValidateSet("Low", "High", "Both")]
    [string]$Test = "Both"
)

# Path to the standalone banner script
$bannerFile = Join-Path $PSScriptRoot "banner_popup.ps1"

# ─────────────────────────────────────────────────────────────────────────────
# Show-TestBanner — launches banner_popup.ps1, waits for it to close
# ─────────────────────────────────────────────────────────────────────────────
function Show-TestBanner {
    param([string]$Title, [string]$Message, [string]$Level = "Low")

    $cmd     = "& '$($bannerFile -replace "'","''")' -Title '$($Title -replace "'","''")' -Message '$($Message -replace "'","''")' -Level '$Level'"
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))

    # -Wait so banners show sequentially in test mode
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded" `
        -WindowStyle Hidden `
        -Wait
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================"
Write-Host "  Battery Monitor - Banner Test Tool"
Write-Host "========================================"
Write-Host ""

if ($Test -eq "Low" -or $Test -eq "Both") {
    Write-Host "Showing LOW battery banner (dismiss or wait 15s)..."
    Show-TestBanner `
        -Title   "Battery Low (20%)" `
        -Message "Battery low. Plug in your charger now to protect battery health." `
        -Level   "Low"
    Write-Host "  OK - Low banner closed."
    Write-Host ""
}

if ($Test -eq "High" -or $Test -eq "Both") {
    Write-Host "Showing HIGH battery banner (dismiss or wait 15s)..."
    Show-TestBanner `
        -Title   "Battery High (80%)" `
        -Message "Unplug your charger to protect battery health." `
        -Level   "High"
    Write-Host "  OK - High banner closed."
    Write-Host ""
}

Write-Host "Test complete. Run battery_monitor.ps1 to start real monitoring."
Write-Host ""