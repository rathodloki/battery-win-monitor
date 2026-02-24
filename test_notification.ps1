Add-Type -AssemblyName System.Windows.Forms
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -Id $pid).Path)
$notify.Visible = $True
$notify.BalloonTipTitle = "Battery Monitor Test"
$notify.BalloonTipText = "If you see this, notifications are working!"
$notify.BalloonTipIcon = "Info"
$notify.ShowBalloonTip(5000)
Start-Sleep -Seconds 5
$notify.Dispose()
