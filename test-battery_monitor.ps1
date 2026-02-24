<#
.SYNOPSIS
    Test script for battery_monitor banners.
.USAGE
    .\test-battery_monitor.ps1              # shows both banners (Low then High)
    .\test-battery_monitor.ps1 -Test Low    # only the LOW banner
    .\test-battery_monitor.ps1 -Test High   # only the HIGH banner
#>

param(
    [ValidateSet("Low", "High", "Both")]
    [string]$Test = "Both"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ─────────────────────────────────────────────────────────────────────────────
# BANNER SCRIPTBLOCK — runs in its own Runspace (STA thread)
# ─────────────────────────────────────────────────────────────────────────────
$bannerScript = {
    param([string]$Title, [string]$Message, [string]$Level)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # ── Colours ───────────────────────────────────────────────────────────────
    $accentColor = if ($Level -eq "Low") {
        [System.Drawing.Color]::FromArgb(255, 230, 90, 40)
    } else {
        [System.Drawing.Color]::FromArgb(255, 50, 200, 100)
    }
    $cardBg   = [System.Drawing.Color]::FromArgb(255, 22, 27, 38)
    $white    = [System.Drawing.Color]::White
    $grayText = [System.Drawing.Color]::FromArgb(255, 170, 178, 195)
    $btnBg    = [System.Drawing.Color]::FromArgb(255, 32, 38, 52)
    $fillPct  = if ($Level -eq "Low") { 0.15 } else { 0.88 }

    # ── Full-screen form  ─────────────────────────────────────────────────────
    # Use VirtualScreen so the overlay always covers the FULL primary display
    # regardless of DPI scaling level — do NOT call SetProcessDPIAware(), it
    # breaks the coordinate system and shrinks the window on scaled displays.
    $sw = [System.Windows.Forms.SystemInformation]::VirtualScreen.Width
    $sh = [System.Windows.Forms.SystemInformation]::VirtualScreen.Height

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
    $form.SetBounds(0, 0, $sw, $sh)
    $form.BackColor       = [System.Drawing.Color]::FromArgb(15, 18, 24)
    $form.Opacity         = 0.97
    $form.TopMost         = $true
    $form.ShowInTaskbar   = $false
    $form.AutoScaleMode   = [System.Windows.Forms.AutoScaleMode]::None

    # ── Card ──────────────────────────────────────────────────────────────────
    $cW = [Math]::Min(820, $sw - 120)
    $cH = 290
    $card = New-Object System.Windows.Forms.Panel
    $card.SetBounds(
        [int](($sw - $cW) / 2),
        [int](($sh - $cH) / 2),
        $cW, $cH
    )
    $card.BackColor   = $cardBg
    $form.Controls.Add($card)

    # Left accent stripe
    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.SetBounds(0, 0, 6, $cH)
    $stripe.BackColor = $accentColor
    $card.Controls.Add($stripe)

    # Top accent line
    $topLine = New-Object System.Windows.Forms.Panel
    $topLine.SetBounds(6, 0, $cW - 6, 2)
    $topLine.BackColor = [System.Drawing.Color]::FromArgb(70, $accentColor.R, $accentColor.G, $accentColor.B)
    $card.Controls.Add($topLine)

    # ── Battery icon — 2x supersampled bitmap for crisp HD look ───────────────
    $dispW = 130; $dispH = 80
    $bmpW  = $dispW * 2; $bmpH = $dispH * 2

    $bmp = New-Object System.Drawing.Bitmap($bmpW, $bmpH)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $pen       = New-Object System.Drawing.Pen($accentColor, 7)
    $fillBrush = New-Object System.Drawing.SolidBrush($accentColor)

    $g.DrawRectangle($pen, 4, 20, 192, 92)            # body outline
    $g.FillRectangle($fillBrush, 198, 44, 28, 44)      # terminal nub
    $fw = [int](186 * $fillPct); if ($fw -lt 8) { $fw = 8 }
    $g.FillRectangle($fillBrush, 8, 26, $fw, 80)       # fill bar

    $pen.Dispose(); $fillBrush.Dispose(); $g.Dispose()

    # Downsample 2x -> 1x with HighQualityBicubic for razor-sharp result
    $battBmp = New-Object System.Drawing.Bitmap($dispW, $dispH)
    $gS = [System.Drawing.Graphics]::FromImage($battBmp)
    $gS.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gS.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gS.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $gS.DrawImage($bmp, 0, 0, $dispW, $dispH)
    $gS.Dispose(); $bmp.Dispose()

    $battBox = New-Object System.Windows.Forms.PictureBox
    $battBox.Image     = $battBmp
    $battBox.Size      = New-Object System.Drawing.Size($dispW, $dispH)
    $battBox.SizeMode  = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $battBox.BackColor = [System.Drawing.Color]::Transparent
    $battBox.Location  = New-Object System.Drawing.Point(
        ($cW - $dispW - 36),
        [int](($cH - $dispH) / 2)
    )
    $card.Controls.Add($battBox)

    # ── Title ─────────────────────────────────────────────────────────────────
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.SetBounds(30, 38, $cW - 210, 66)
    $lblTitle.Text      = $Title
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $lblTitle.ForeColor = $white
    $lblTitle.BackColor = [System.Drawing.Color]::Transparent
    $lblTitle.AutoSize  = $false
    $card.Controls.Add($lblTitle)

    # ── Message ───────────────────────────────────────────────────────────────
    $lblMsg = New-Object System.Windows.Forms.Label
    $lblMsg.SetBounds(30, 112, $cW - 210, 76)
    $lblMsg.Text      = $Message
    $lblMsg.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $lblMsg.ForeColor = $grayText
    $lblMsg.BackColor = [System.Drawing.Color]::Transparent
    $lblMsg.AutoSize  = $false
    $card.Controls.Add($lblMsg)

    # ── Dismiss button ────────────────────────────────────────────────────────
    $btn = New-Object System.Windows.Forms.Button
    $btn.SetBounds(30, 222, 140, 44)
    $btn.Text      = "Dismiss"
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderColor = $accentColor
    $btn.FlatAppearance.BorderSize  = 2
    $btn.ForeColor = $accentColor
    $btn.BackColor = $btnBg
    $btn.Font      = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $btn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btn.Add_Click({ $form.Close() })
    $card.Controls.Add($btn)

    # ── X close button ────────────────────────────────────────────────────────
    $xBtn = New-Object System.Windows.Forms.Button
    $xBtn.SetBounds($cW - 44, 6, 36, 36)
    $xBtn.Text      = [char]0x00D7
    $xBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $xBtn.FlatAppearance.BorderSize = 0
    $xBtn.ForeColor = $grayText
    $xBtn.BackColor = [System.Drawing.Color]::Transparent
    $xBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $xBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $xBtn.Add_Click({ $form.Close() })
    $card.Controls.Add($xBtn)

    $form.Add_Click({ $form.Close() })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 15000
    $timer.Add_Tick({ $timer.Stop(); $form.Close() })
    $timer.Start()

    $form.Add_Shown({ $form.Activate() })
    [System.Windows.Forms.Application]::Run($form)
}

# ─────────────────────────────────────────────────────────────────────────────
# Show-TestBanner: proper Runspace on STA thread, blocks until dismissed
# ─────────────────────────────────────────────────────────────────────────────
function Show-TestBanner {
    param([string]$Title, [string]$Message, [string]$Level = "Low")

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::STA
    $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $rs.Open()

    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($bannerScript).AddArgument($Title).AddArgument($Message).AddArgument($Level) | Out-Null
    $ps.Invoke()

    $rs.Close(); $ps.Dispose()
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
