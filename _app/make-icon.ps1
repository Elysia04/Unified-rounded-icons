[CmdletBinding()]
param(
    [int] $Size = 512,
    [string] $OutputName = 'app'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-RoundPath {
    param([int] $X, [int] $Y, [int] $Width, [int] $Height, [int] $Radius)
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $d = $Radius * 2
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc($X + $Width - $d, $Y, $d, $d, 270, 90)
    $path.AddArc($X + $Width - $d, $Y + $Height - $d, $d, $d, 0, 90)
    $path.AddArc($X, $Y + $Height - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

$source = Join-Path $PSScriptRoot "$OutputName-source.png"
$target = Join-Path $PSScriptRoot "$OutputName.ico"

$bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $tile = New-RoundPath 0 0 $Size $Size ([int][math]::Round($Size * 0.225))
    $gradient = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        [System.Drawing.Rectangle]::new(0, 0, $Size, $Size),
        [System.Drawing.Color]::FromArgb(255, 0x5C, 0x9C, 0xFF),
        [System.Drawing.Color]::FromArgb(255, 0x1E, 0x55, 0xC8),
        [single]90
    )
    $graphics.FillPath($gradient, $tile)

    $innerSize = [int][math]::Round($Size * 0.44)
    $innerOffset = [int](($Size - $innerSize) / 2)
    $inner = New-RoundPath $innerOffset $innerOffset $innerSize $innerSize ([int][math]::Round($innerSize * 0.3))
    $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 0xFF, 0xFF, 0xFF))
    $graphics.FillPath($white, $inner)
}
finally {
    $graphics.Dispose()
}

$bitmap.Save($source, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()

$engine = Join-Path (Split-Path -Parent $PSScriptRoot) '_engine\png-jpg-to-ico.ps1'
$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $engine `
    -InputPath $source -OutputDir $PSScriptRoot -RadiusPercent 28 -PaddingPercent 0 -NoOpenDialog

$generated = Join-Path $PSScriptRoot "$OutputName-source.ico"
if (-not (Test-Path -LiteralPath $generated)) {
    throw "转换图标失败，没有生成 $generated"
}
Move-Item -LiteralPath $generated -Destination $target -Force
Write-Host "已生成应用图标：$target"