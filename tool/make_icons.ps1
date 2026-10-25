# Draws the app icon (a paint palette and brush on the app's gradient) and
# writes every size Android, the web build and the in-app logo need.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File tool\make_icons.ps1
param([string]$Root = (Split-Path $PSScriptRoot -Parent))

Add-Type -AssemblyName System.Drawing

function Col([string]$hex, [int]$alpha = 255) {
    [System.Drawing.Color]::FromArgb($alpha, [System.Drawing.ColorTranslator]::FromHtml($hex))
}

# Violet -> pink -> peach, matching AppTheme.headerGradient.
function Fill-Gradient($g, [float]$size, [bool]$rounded) {
    $rect = New-Object System.Drawing.RectangleF 0, 0, $size, $size
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, (Col '#7F5AF0'), (Col '#FFB86B'), 45.0
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
    $blend.Colors = @((Col '#7F5AF0'), (Col '#FF6FB5'), (Col '#FFB86B'))
    $blend.Positions = @([float]0, [float]0.5, [float]1)
    $brush.InterpolationColors = $blend
    if ($rounded) {
        $r = $size * 0.44
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0, 0, $r, $r, 180, 90)
        $path.AddArc($size - $r, 0, $r, $r, 270, 90)
        $path.AddArc($size - $r, $size - $r, $r, $r, 0, 90)
        $path.AddArc(0, $size - $r, $r, $r, 90, 90)
        $path.CloseFigure()
        $g.FillPath($brush, $path)
    } else {
        $g.FillRectangle($brush, $rect)
    }
}

# The palette and brush, drawn in Android's 108-unit adaptive icon space
# (the safe zone is the central 66 units).
function Draw-Foreground($g) {
    $palette = New-Object System.Drawing.Drawing2D.GraphicsPath ([System.Drawing.Drawing2D.FillMode]::Alternate)
    $palette.AddEllipse(25, 35, 50, 42)
    $palette.AddEllipse(55, 61, 10, 10)   # thumb hole

    $shadow = $palette.Clone()
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate(1.5, 2.5)
    $shadow.Transform($m)
    $g.FillPath((New-Object System.Drawing.SolidBrush (Col '#000000' 45)), $shadow)
    $g.FillPath((New-Object System.Drawing.SolidBrush (Col '#FFFFFF')), $palette)

    foreach ($dot in @(@(37, 52, '#FF5A5F'), @(45, 43, '#FFD23F'), @(57, 42, '#3DDC97'),
                       @(36, 64, '#3DA9FC'), @(48, 67, '#9B5DE5'))) {
        $g.FillEllipse((New-Object System.Drawing.SolidBrush (Col $dot[2])), $dot[0] - 5, $dot[1] - 5, 10, 10)
    }

    $round = [System.Drawing.Drawing2D.LineCap]::Round
    $outline = New-Object System.Drawing.Pen (Col '#FFFFFF'), 8.5
    $outline.StartCap = $round; $outline.EndCap = $round
    $g.DrawLine($outline, 77, 29, 62, 49)
    $handle = New-Object System.Drawing.Pen (Col '#6D4C41'), 5.5
    $handle.StartCap = $round; $handle.EndCap = $round
    $g.DrawLine($handle, 77, 29, 64, 46)
    $ferrule = New-Object System.Drawing.Pen (Col '#B0BEC5'), 7
    $g.DrawLine($ferrule, 64.6, 45.2, 60.7, 50.4)

    $tip = New-Object System.Drawing.Drawing2D.GraphicsPath
    $tip.AddLine([float]58.3, [float]48.6, [float]63.1, [float]52.2)
    $tip.AddBezier([float]63.1, [float]52.2, [float]62.5, [float]56, [float]58.5, [float]59, [float]53, [float]61.5)
    $tip.AddBezier([float]53, [float]61.5, [float]54.5, [float]57, [float]56, [float]52, [float]58.3, [float]48.6)
    $tip.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush (Col '#7F5AF0')), $tip)
}

# Kinds: full (rounded tile, cropped to the artwork), fg / bg (adaptive
# layers), maskable (full-bleed square for web).
function Save-Icon([string]$kind, [int]$size, [string]$relPath, [switch]$Opaque) {
    # The App Store rejects icons with an alpha channel.
    $bmp = if ($Opaque) {
        New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    } else {
        New-Object System.Drawing.Bitmap $size, $size
    }
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    if ($kind -ne 'fg') { Fill-Gradient $g $size ($kind -eq 'full') }
    if ($kind -ne 'bg') {
        if ($kind -eq 'full') {
            $g.ScaleTransform($size / 76.0, $size / 76.0)
            $g.TranslateTransform(-16, -16)
        } else {
            $g.ScaleTransform($size / 108.0, $size / 108.0)
        }
        Draw-Foreground $g
    }

    $out = Join-Path $Root $relPath
    New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output "wrote $relPath ($size px)"
}

$res = 'android/app/src/main/res'
$densities = [ordered]@{ mdpi = 1.0; hdpi = 1.5; xhdpi = 2.0; xxhdpi = 3.0; xxxhdpi = 4.0 }
foreach ($d in $densities.Keys) {
    $k = $densities[$d]
    Save-Icon 'full' ([int](48 * $k)) "$res/mipmap-$d/ic_launcher.png"
    Save-Icon 'fg' ([int](108 * $k)) "$res/mipmap-$d/ic_launcher_foreground.png"
    Save-Icon 'bg' ([int](108 * $k)) "$res/mipmap-$d/ic_launcher_background.png"
}

$adaptive = Join-Path $Root "$res/mipmap-anydpi-v26/ic_launcher.xml"
New-Item -ItemType Directory -Force (Split-Path $adaptive) | Out-Null
Set-Content -Encoding utf8 $adaptive @'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'@
Write-Output "wrote $res/mipmap-anydpi-v26/ic_launcher.xml"

Save-Icon 'full' 192 'web/icons/Icon-192.png'
Save-Icon 'full' 512 'web/icons/Icon-512.png'
Save-Icon 'maskable' 192 'web/icons/Icon-maskable-192.png'
Save-Icon 'maskable' 512 'web/icons/Icon-maskable-512.png'
Save-Icon 'full' 32 'web/favicon.png'
Save-Icon 'full' 256 'assets/icon/logo.png'

# iOS: one square, opaque 1024 px icon; Xcode makes the smaller sizes and iOS
# rounds the corners itself. The palette sits in the same safe middle as on
# Android's adaptive icon.
Save-Icon 'maskable' 1024 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png' -Opaque
