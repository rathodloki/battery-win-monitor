<#
.SYNOPSIS
    Standalone banner popup for Battery Monitor.
    Launched by battery_monitor.ps1 / test-battery_monitor.ps1 via Start-Process.
#>
param(
    [string]$Title   = "Battery Alert",
    [string]$Message = "Check your battery.",
    [string]$Level   = "Low"
)

# ── DPI awareness MUST be set BEFORE loading Windows.Forms ───────────────────
# In a fresh process (which this always is), SetProcessDPIAware works correctly:
# the form renders at native resolution instead of being bitmap-scaled (blurry).
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DpiSetup {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@ -ErrorAction SilentlyContinue
try { [DpiSetup]::SetProcessDPIAware() | Out-Null } catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── Win11 DWM: native drop shadow + rounded corners ──────────────────────────
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win11Dwm {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    [DllImport("dwmapi.dll")]
    public static extern int DwmExtendFrameIntoClientArea(IntPtr hWnd, ref MARGINS pMarInset);

    public struct MARGINS { public int cxLeftWidth, cxRightWidth, cyTopHeight, cyBottomHeight; }

    public static void ApplyShadowAndCorners(IntPtr handle) {
        int DWMWCP_ROUND = 2;
        DwmSetWindowAttribute(handle, 33, ref DWMWCP_ROUND, 4);
        var m = new MARGINS() { cxLeftWidth=1, cxRightWidth=1, cyTopHeight=1, cyBottomHeight=1 };
        DwmExtendFrameIntoClientArea(handle, ref m);
    }
}
"@ -ErrorAction SilentlyContinue

# ── Helper: rounded GraphicsPath ─────────────────────────────────────────────
function Get-RoundedPath([System.Drawing.Rectangle]$rect, [int]$rad) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($rect.X,            $rect.Y,             $rad, $rad, 180, 90)
    $path.AddArc($rect.Right - $rad, $rect.Y,             $rad, $rad, 270, 90)
    $path.AddArc($rect.Right - $rad, $rect.Bottom - $rad, $rad, $rad, 0,   90)
    $path.AddArc($rect.X,            $rect.Bottom - $rad, $rad, $rad, 90,  90)
    $path.CloseFigure()
    return $path
}

# ── Colours ───────────────────────────────────────────────────────────────────
$accentColor = if ($Level -eq "Low") {
    [System.Drawing.Color]::FromArgb(255, 255, 87, 34)
} else {
    [System.Drawing.Color]::FromArgb(255, 46, 213, 115)
}
$cardBg   = [System.Drawing.Color]::FromArgb(255, 22, 27, 38)
$white    = [System.Drawing.Color]::White
$grayText = [System.Drawing.Color]::FromArgb(255, 170, 178, 195)
$btnBg    = [System.Drawing.Color]::FromArgb(255, 32, 38, 52)
$fillPct  = if ($Level -eq "Low") { 0.15 } else { 0.88 }

# ── Form ──────────────────────────────────────────────────────────────────────
$cW = 820; $cH = 290

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Size            = New-Object System.Drawing.Size($cW, $cH)
$form.BackColor       = $cardBg
$form.Opacity         = 0
$form.TopMost         = $true
$form.ShowInTaskbar   = $false
$form.AutoScaleMode   = [System.Windows.Forms.AutoScaleMode]::None

$form.Add_HandleCreated({
    try { [Win11Dwm]::ApplyShadowAndCorners($form.Handle) } catch {}
})

# Left accent stripe
$stripe = New-Object System.Windows.Forms.Panel
$stripe.SetBounds(0, 0, 8, $cH)
$stripe.BackColor = $accentColor
$form.Controls.Add($stripe)

# Top accent line
$topLine = New-Object System.Windows.Forms.Panel
$topLine.SetBounds(8, 0, $cW - 8, 1)
$topLine.BackColor = [System.Drawing.Color]::FromArgb(60, $accentColor.R, $accentColor.G, $accentColor.B)
$form.Controls.Add($topLine)

# ── Battery icon — 2x supersampled, rounded paths ────────────────────────────
$dispW = 140; $dispH = 80
$bmpW  = $dispW * 2; $bmpH = $dispH * 2

$bmp = New-Object System.Drawing.Bitmap($bmpW, $bmpH)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)

$outlinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 235, 235, 235), 10)
$fillBrush  = New-Object System.Drawing.SolidBrush($accentColor)
$nubBrush   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 235, 235, 235))

$outerRect = New-Object System.Drawing.Rectangle(10, 20, 220, 120)
$outerPath = Get-RoundedPath $outerRect 24
$g.DrawPath($outlinePen, $outerPath)

$nubPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$nubPath.AddArc(226, 50, 24, 24, 270, 90)
$nubPath.AddArc(226, 86, 24, 24, 0,   90)
$nubPath.AddLine(250, 110, 232, 110)
$nubPath.AddLine(232, 50,  250, 50)
$nubPath.CloseFigure()
$g.FillPath($nubBrush, $nubPath)

$pad         = 14
$innerMaxW   = $outerRect.Width - ($pad * 2) - 8
$actualFillW = [int]($innerMaxW * $fillPct)
if ($actualFillW -lt 20) { $actualFillW = 20 }
$innerRect = New-Object System.Drawing.Rectangle(
    ($outerRect.X + $pad + 4), ($outerRect.Y + $pad + 4),
    $actualFillW, ($outerRect.Height - ($pad * 2) - 8)
)
$innerPath = Get-RoundedPath $innerRect 12
$g.FillPath($fillBrush, $innerPath)

$outlinePen.Dispose(); $fillBrush.Dispose(); $nubBrush.Dispose(); $g.Dispose()

$battBmp = New-Object System.Drawing.Bitmap($dispW, $dispH)
$gS = [System.Drawing.Graphics]::FromImage($battBmp)
$gS.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gS.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$gS.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$gS.DrawImage($bmp, 0, 0, $dispW, $dispH)
$gS.Dispose(); $bmp.Dispose()

$battBox = New-Object System.Windows.Forms.PictureBox
$battBox.Image     = $battBmp
$battBox.Size      = New-Object System.Drawing.Size($dispW, $dispH)
$battBox.BackColor = [System.Drawing.Color]::Transparent
$battBox.SizeMode  = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
$battBox.Location  = New-Object System.Drawing.Point(($cW - $dispW - 40), [int](($cH - $dispH) / 2))
$form.Controls.Add($battBox)

# ── Title ─────────────────────────────────────────────────────────────────────
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.SetBounds(36, 36, $cW - 220, 70)
$lblTitle.Text      = $Title
$lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 26, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
$lblTitle.ForeColor = $white
$lblTitle.BackColor = [System.Drawing.Color]::Transparent
$lblTitle.AutoSize  = $false
$form.Controls.Add($lblTitle)

# ── Message ───────────────────────────────────────────────────────────────────
$lblMsg = New-Object System.Windows.Forms.Label
$lblMsg.SetBounds(38, 108, $cW - 220, 76)
$lblMsg.Text      = $Message
$lblMsg.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
$lblMsg.ForeColor = $grayText
$lblMsg.BackColor = [System.Drawing.Color]::Transparent
$lblMsg.AutoSize  = $false
$form.Controls.Add($lblMsg)

# ── Dismiss button ────────────────────────────────────────────────────────────
$btn = New-Object System.Windows.Forms.Button
$btn.SetBounds(38, 210, 150, 46)
$btn.Text      = "Dismiss"
$btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btn.FlatAppearance.BorderColor = $accentColor
$btn.FlatAppearance.BorderSize  = 2
$btn.ForeColor = $accentColor
$btn.BackColor = $btnBg
$btn.Font      = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
$btn.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btn.Add_MouseEnter({ $btn.BackColor = $accentColor; $btn.ForeColor = $cardBg })
$btn.Add_MouseLeave({ $btn.BackColor = $btnBg;       $btn.ForeColor = $accentColor })
$btn.Add_Click({ $form.Close() })
$form.Controls.Add($btn)

# ── X close button ────────────────────────────────────────────────────────────
$xBtn = New-Object System.Windows.Forms.Button
$xBtn.SetBounds($cW - 46, 12, 34, 34)
$xBtn.Text      = [char]0x00D7
$xBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$xBtn.FlatAppearance.BorderSize = 0
$xBtn.ForeColor = $grayText
$xBtn.BackColor = [System.Drawing.Color]::Transparent
$xBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
$xBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
$xBtn.Add_MouseEnter({ $xBtn.ForeColor = $white;    $xBtn.BackColor = [System.Drawing.Color]::FromArgb(30,255,255,255) })
$xBtn.Add_MouseLeave({ $xBtn.ForeColor = $grayText; $xBtn.BackColor = [System.Drawing.Color]::Transparent })
$xBtn.Add_Click({ $form.Close() })
$form.Controls.Add($xBtn)

$form.Add_Click({ $form.Close() })

# ── Fade-in animation ─────────────────────────────────────────────────────────
$fadeTimer = New-Object System.Windows.Forms.Timer
$fadeTimer.Interval = 15
$fadeTimer.Add_Tick({
    if ($form.Opacity -lt 0.99) { $form.Opacity += 0.06 }
    else { $form.Opacity = 1.0; $fadeTimer.Stop(); $fadeTimer.Dispose() }
})
$form.Add_Load({ $fadeTimer.Start() })

# ── Auto-dismiss after 15 seconds ─────────────────────────────────────────────
$autoTimer = New-Object System.Windows.Forms.Timer
$autoTimer.Interval = 15000
$autoTimer.Add_Tick({ $autoTimer.Stop(); $form.Close() })
$autoTimer.Start()

$form.Add_Shown({ $form.Activate() })
[System.Windows.Forms.Application]::Run($form)
