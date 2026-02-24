<#
.SYNOPSIS
    Test script for battery_monitor banners (Custom UI + Native Win 11 Shadow).
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

    # Hook into Windows DWM API to force the Native Drop Shadow & Rounded Corners
    $csharp = @"
    using System;
    using System.Runtime.InteropServices;
    public class Win11Dwm {
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        [DllImport("dwmapi.dll")]
        public static extern int DwmExtendFrameIntoClientArea(IntPtr hWnd, ref MARGINS pMarInset);

        public struct MARGINS {
            public int cxLeftWidth;
            public int cxRightWidth;
            public int cyTopHeight;
            public int cyBottomHeight;
        }
        
        public static void ApplyShadowAndCorners(IntPtr handle) {
            // Force Windows 11 Native Rounded Corners
            int DWMWCP_ROUND = 2;
            DwmSetWindowAttribute(handle, 33, ref DWMWCP_ROUND, 4);

            // Extend frame by 1px to trigger the native OS Drop Shadow
            var margins = new MARGINS() { cxLeftWidth = 1, cxRightWidth = 1, cyTopHeight = 1, cyBottomHeight = 1 };
            DwmExtendFrameIntoClientArea(handle, ref margins);
        }
    }
"@
    try { Add-Type -TypeDefinition $csharp -ErrorAction Ignore } catch { }

    # ── Helpers ───────────────────────────────────────────────────────────────
    $getRoundedRect = {
        param([System.Drawing.Rectangle]$rect, [int]$rad)
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc($rect.X, $rect.Y, $rad, $rad, 180, 90)
        $path.AddArc($rect.Right - $rad, $rect.Y, $rad, $rad, 270, 90)
        $path.AddArc($rect.Right - $rad, $rect.Bottom - $rad, $rad, $rad, 0, 90)
        $path.AddArc($rect.X, $rect.Bottom - $rad, $rad, $rad, 90, 90)
        $path.CloseFigure()
        return $path
    }

    # ── Colours ───────────────────────────────────────────────────────────────
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

    # ── Main Floating Form (This IS the Card now) ─────────────────────────────
    $cW = 820
    $cH = 290

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.Size            = New-Object System.Drawing.Size($cW, $cH)
    $form.BackColor       = $cardBg
    $form.Opacity         = 0 # Start invisible for fade-in animation
    $form.TopMost         = $true
    $form.ShowInTaskbar   = $false

    # Apply Native Shadow and Corners as soon as the window handle is created
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

    # ── Battery icon — Redesigned to match requested reference image ──────────
    $dispW = 140; $dispH = 80
    $bmpW  = $dispW * 2; $bmpH = $dispH * 2

    $bmp = New-Object System.Drawing.Bitmap($bmpW, $bmpH)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $outlinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 235, 235, 235), 10)
    $fillBrush  = New-Object System.Drawing.SolidBrush($accentColor)
    $nubBrush   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 235, 235, 235))

    # Outer Shell
    $outerRect = New-Object System.Drawing.Rectangle(10, 20, 220, 120)
    $outerPath = & $getRoundedRect $outerRect 24
    $g.DrawPath($outlinePen, $outerPath)

    # Terminal Nub (Right side)
    $nubPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $nubPath.AddArc(226, 50, 24, 24, 270, 90)
    $nubPath.AddArc(226, 86, 24, 24, 0, 90)
    $nubPath.AddLine(250, 110, 232, 110)
    $nubPath.AddLine(232, 50, 250, 50)
    $nubPath.CloseFigure()
    $g.FillPath($nubBrush, $nubPath)

    # Inner Fill (With clean padding gap)
    $pad = 14
    $innerMaxW = $outerRect.Width - ($pad * 2) - 8
    $actualFillW = [int]($innerMaxW * $fillPct)
    if ($actualFillW -lt 20) { $actualFillW = 20 }

    $innerRect = New-Object System.Drawing.Rectangle(
        ($outerRect.X + $pad + 4), 
        ($outerRect.Y + $pad + 4), 
        $actualFillW, 
        ($outerRect.Height - ($pad * 2) - 8)
    )
    $innerPath = & $getRoundedRect $innerRect 12
    $g.FillPath($fillBrush, $innerPath)

    $outlinePen.Dispose(); $fillBrush.Dispose(); $nubBrush.Dispose(); $g.Dispose()

    # Downsample for perfect crispness
    $battBmp = New-Object System.Drawing.Bitmap($dispW, $dispH)
    $gS = [System.Drawing.Graphics]::FromImage($battBmp)
    $gS.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gS.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gS.DrawImage($bmp, 0, 0, $dispW, $dispH)
    $gS.Dispose(); $bmp.Dispose()

    $battBox = New-Object System.Windows.Forms.PictureBox
    $battBox.Image     = $battBmp
    $battBox.Size      = New-Object System.Drawing.Size($dispW, $dispH)
    $battBox.BackColor = [System.Drawing.Color]::Transparent
    $battBox.Location  = New-Object System.Drawing.Point(
        ($cW - $dispW - 40),
        [int](($cH - $dispH) / 2)
    )
    $form.Controls.Add($battBox)

    # ── Title ─────────────────────────────────────────────────────────────────
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.SetBounds(36, 36, $cW - 220, 70) 
    $lblTitle.Text      = $Title
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 26, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
    $lblTitle.ForeColor = $white
    $lblTitle.BackColor = [System.Drawing.Color]::Transparent
    $lblTitle.AutoSize  = $false
    $form.Controls.Add($lblTitle)

    # ── Message ───────────────────────────────────────────────────────────────
    $lblMsg = New-Object System.Windows.Forms.Label
    $lblMsg.SetBounds(38, 108, $cW - 220, 76)
    $lblMsg.Text      = $Message
    $lblMsg.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $lblMsg.ForeColor = $grayText
    $lblMsg.BackColor = [System.Drawing.Color]::Transparent
    $lblMsg.AutoSize  = $false
    $form.Controls.Add($lblMsg)

    # ── Dismiss button ────────────────────────────────────────────────────────
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
    
    $btn.Add_MouseEnter({
        $this.BackColor = $accentColor
        $this.ForeColor = $cardBg
    })
    $btn.Add_MouseLeave({
        $this.BackColor = $btnBg
        $this.ForeColor = $accentColor
    })
    $btn.Add_Click({ $form.Close() })
    $form.Controls.Add($btn)

    # ── X close button ────────────────────────────────────────────────────────
    $xBtn = New-Object System.Windows.Forms.Button
    $xBtn.SetBounds($cW - 46, 12, 34, 34)
    $xBtn.Text      = [char]0x00D7
    $xBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $xBtn.FlatAppearance.BorderSize = 0
    $xBtn.ForeColor = $grayText
    $xBtn.BackColor = [System.Drawing.Color]::Transparent
    $xBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
    $xBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    
    $xBtn.Add_MouseEnter({
        $this.ForeColor = $white
        $this.BackColor = [System.Drawing.Color]::FromArgb(30, 255, 255, 255)
    })
    $xBtn.Add_MouseLeave({
        $this.ForeColor = $grayText
        $this.BackColor = [System.Drawing.Color]::Transparent
    })
    $xBtn.Add_Click({ $form.Close() })
    $form.Controls.Add($xBtn)

    $form.Add_Click({ $form.Close() })

    # ── Fade-in Animation Timer ───────────────────────────────────────────────
    $fadeTimer = New-Object System.Windows.Forms.Timer
    $fadeTimer.Interval = 15
    $fadeTimer.Add_Tick({
        if ($form.Opacity -lt 0.99) {
            $form.Opacity += 0.06
        } else {
            $form.Opacity = 1.0
            $fadeTimer.Stop()
            $fadeTimer.Dispose()
        }
    })
    $form.Add_Load({ $fadeTimer.Start() })

    # Auto-close timer
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 15000
    $timer.Add_Tick({ $timer.Stop(); $form.Close() })
    $timer.Start()

    $form.Add_Shown({ $form.Activate() })
    [System.Windows.Forms.Application]::Run($form)
}

# ─────────────────────────────────────────────────────────────────────────────
# Show-TestBanner
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
Write-Host "  Battery Monitor - Custom + Native OS Shadow"
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