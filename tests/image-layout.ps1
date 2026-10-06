#requires -Version 5.1
[CmdletBinding()]
param([string] $EdgeSource, [string] $EngineExecutable)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$enginePath = Join-Path (Split-Path -Parent $PSScriptRoot) '_engine\png-jpg-to-ico.ps1'
$tokens = $null
$parseErrors = $null
if ($EngineExecutable) {
    $assembly = [System.Reflection.Assembly]::LoadFile([System.IO.Path]::GetFullPath($EngineExecutable))
    $stream = $assembly.GetManifestResourceStream('RoundedIcoApp.Converter.ps1')
    if ($null -eq $stream) { throw 'The executable does not contain the converter engine.' }
    $reader = [System.IO.StreamReader]::new($stream)
    try { $embeddedEngine = $reader.ReadToEnd() }
    finally { $reader.Dispose() }
    if ($embeddedEngine -ne [System.IO.File]::ReadAllText($enginePath)) {
        throw 'The executable contains an outdated engine.'
    }
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($embeddedEngine, [ref]$tokens, [ref]$parseErrors)
}
else {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($enginePath, [ref]$tokens, [ref]$parseErrors)
}
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
# Load engine functions without executing its interactive entry point.
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        . ([scriptblock]::Create($statement.Extent.Text))
    }
}

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Read-PngBytes {
    param([byte[]] $Bytes)
    $stream = [System.IO.MemoryStream]::new($Bytes)
    $decoded = $null
    try {
        $decoded = [System.Drawing.Bitmap]::new($stream)
        return $decoded.Clone([System.Drawing.Rectangle]::new(0, 0, $decoded.Width, $decoded.Height), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    }
    finally {
        if ($null -ne $decoded) { $decoded.Dispose() }
        $stream.Dispose()
    }
}

function Get-RedBounds {
    param([System.Drawing.Bitmap] $Image)
    $left = $Image.Width
    $top = $Image.Height
    $right = -1
    $bottom = -1
    for ($y = 0; $y -lt $Image.Height; $y++) {
        for ($x = 0; $x -lt $Image.Width; $x++) {
            $pixel = $Image.GetPixel($x, $y)
            if ($pixel.A -gt 200 -and $pixel.R -gt 200 -and $pixel.G -lt 50 -and $pixel.B -lt 50) {
                $left = [math]::Min($left, $x)
                $top = [math]::Min($top, $y)
                $right = [math]::Max($right, $x)
                $bottom = [math]::Max($bottom, $y)
            }
        }
    }
    Assert-True ($right -ge $left) 'The artwork disappeared.'
    return [System.Drawing.Rectangle]::FromLTRB($left, $top, $right + 1, $bottom + 1)
}

function Assert-ColorNear {
    param([System.Drawing.Color] $Actual, [System.Drawing.Color] $Expected, [string] $Message, [int] $Tolerance = 12)
    Assert-True (
        [math]::Abs([int]$Actual.R - $Expected.R) -le $Tolerance -and
        [math]::Abs([int]$Actual.G - $Expected.G) -le $Tolerance -and
        [math]::Abs([int]$Actual.B - $Expected.B) -le $Tolerance
    ) "$Message Actual: $Actual; expected: $Expected."
}

$images = [System.Collections.Generic.List[System.Drawing.Bitmap]]::new()
$icoPath = Join-Path ([System.IO.Path]::GetTempPath()) ("RoundedIcoTest-" + [guid]::NewGuid().ToString('N') + '.ico')
try {
    # A wide, off-center logo must retain both ends and its 7:1 proportions.
    $wide = [System.Drawing.Bitmap]::new(320, 100)
    $images.Add($wide)
    $graphics = [System.Drawing.Graphics]::FromImage($wide)
    try {
        $graphics.Clear([System.Drawing.Color]::White)
        $graphics.FillRectangle([System.Drawing.Brushes]::Red, 10, 30, 280, 40)
    }
    finally { $graphics.Dispose() }
    $bounds = Get-UniformContentBounds $wide
    Assert-True ($bounds.Width -gt $wide.Height) 'The wide fixture must exceed the short source dimension.'
    $rounded = Read-PngBytes (New-RoundedPngBytes -Source $wide -Size 256 -RadiusPercent 28 -PaddingPercent 0 -ContentBounds $bounds)
    $images.Add($rounded)
    $redBounds = Get-RedBounds $rounded
    Assert-True ([math]::Abs($redBounds.Width / [double]$redBounds.Height - 7) -lt 0.25) 'Trimming changed the logo aspect ratio or cropped an end.'
    Assert-True ($redBounds.Left -ge 24 -and $redBounds.Right -le 232) 'Trimmed artwork needs internal spacing.'
    Assert-True ([math]::Abs(($redBounds.Left + $redBounds.Right) / 2.0 - 128) -le 1) 'Trimmed artwork is not centered.'
    Write-Output 'PASS: wide artwork keeps its proportions, ends, spacing and center.'

    # At maximum corner radius, even a solid square must stay inside the mask.
    $square = [System.Drawing.Bitmap]::new(200, 200)
    $images.Add($square)
    $graphics = [System.Drawing.Graphics]::FromImage($square)
    try {
        $graphics.Clear([System.Drawing.Color]::White)
        $graphics.FillRectangle([System.Drawing.Brushes]::Red, 40, 40, 120, 120)
    }
    finally { $graphics.Dispose() }
    $bounds = Get-UniformContentBounds $square
    foreach ($radius in @(0, 28, 50)) {
        foreach ($padding in @(0, 20)) {
            $rendered = Read-PngBytes (New-RoundedPngBytes -Source $square -Size 128 -RadiusPercent $radius -PaddingPercent $padding -ContentBounds $bounds)
            $images.Add($rendered)
            $redBounds = Get-RedBounds $rendered
            foreach ($point in @(
                [System.Drawing.Point]::new($redBounds.Left, $redBounds.Top),
                [System.Drawing.Point]::new($redBounds.Right - 1, $redBounds.Top),
                [System.Drawing.Point]::new($redBounds.Left, $redBounds.Bottom - 1),
                [System.Drawing.Point]::new($redBounds.Right - 1, $redBounds.Bottom - 1)
            )) {
                $pixel = $rendered.GetPixel($point.X, $point.Y)
                Assert-True ($pixel.A -eq 255 -and $pixel.R -gt 200 -and $pixel.G -lt 100) "The rounded mask clipped artwork at radius $radius, padding $padding, point $point, pixel $pixel."
            }
            if ($padding -gt 0) {
                Assert-True ($rendered.GetPixel(0, 64).A -eq 0) 'External transparent padding was lost.'
            }
        }
    }
    Write-Output 'PASS: artwork survives radius 0/28/50 and padding 0/20.'

    # Full-bleed colored artwork used to be repainted with the corner color.
    $disc = [System.Drawing.Bitmap]::new(200, 200)
    $images.Add($disc)
    $graphics = [System.Drawing.Graphics]::FromImage($disc)
    try {
        $graphics.Clear([System.Drawing.Color]::White)
        $graphics.FillEllipse([System.Drawing.Brushes]::Red, 0, 0, 200, 200)
    }
    finally { $graphics.Dispose() }
    $discOutput = Read-PngBytes (New-RoundedPngBytes -Source $disc -Size 128 -RadiusPercent 28 -PaddingPercent 0)
    $images.Add($discOutput)
    $edge = $discOutput.GetPixel(2, 64)
    Assert-True ($edge.A -eq 255 -and $edge.R -gt 200 -and $edge.G -lt 50) 'The colored edge was repainted.'
    Write-Output 'PASS: full-bleed colored edges remain intact.'

    # Transparent black outside a tile must not introduce a black fringe.
    $tile = [System.Drawing.Bitmap]::new(200, 200)
    $images.Add($tile)
    $graphics = [System.Drawing.Graphics]::FromImage($tile)
    $path = New-RoundedRectanglePath -X 0 -Y 0 -Width 200 -Height 200 -Radius 56
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.FillPath([System.Drawing.Brushes]::DodgerBlue, $path)
    }
    finally { $path.Dispose(); $graphics.Dispose() }
    $tileOutput = Read-PngBytes (New-RoundedPngBytes -Source $tile -Size 64 -RadiusPercent 28 -PaddingPercent 0)
    $images.Add($tileOutput)
    $partialCount = 0
    for ($y = 0; $y -lt 64; $y++) {
        for ($x = 0; $x -lt 64; $x++) {
            $pixel = $tileOutput.GetPixel($x, $y)
            if ($pixel.A -gt 0 -and $pixel.A -lt 255) {
                $partialCount++
                Assert-ColorNear $pixel ([System.Drawing.Color]::DodgerBlue) "An anti-aliased edge became dark at $x, ${y}."
            }
        }
    }
    Assert-True ($partialCount -gt 0) 'Rounded edges lost anti-aliasing.'
    Write-Output 'PASS: transparent source edges stay colored and anti-aliased.'

    # Large single-color artwork must not be mistaken for the background.
    foreach ($backgroundName in @('White', 'Black', 'Red', 'RoyalBlue', 'ForestGreen', 'Orange', 'Purple', 'Gray', 'Transparent')) {
        foreach ($foregroundName in @('White', 'Black', 'Red', 'Lime', 'Blue', 'Yellow')) {
            $background = [System.Drawing.Color]::FromName($backgroundName)
            $foreground = [System.Drawing.Color]::FromName($foregroundName)
            if ($background.ToArgb() -eq $foreground.ToArgb()) { continue }
            $fixture = [System.Drawing.Bitmap]::new(200, 200)
            $images.Add($fixture)
            $graphics = [System.Drawing.Graphics]::FromImage($fixture)
            $brush = [System.Drawing.SolidBrush]::new($foreground)
            try {
                $graphics.Clear($background)
                $graphics.FillRectangle($brush, 10, 10, 180, 180)
            }
            finally { $brush.Dispose(); $graphics.Dispose() }
            $bounds = Get-UniformContentBounds $fixture
            Assert-True ($bounds.Width -lt 200 -and $bounds.Height -lt 200) "A uniform $backgroundName border was not trimmed."
            $rendered = Read-PngBytes (New-RoundedPngBytes -Source $fixture -Size 64 -RadiusPercent 28 -PaddingPercent 0 -ContentBounds $bounds)
            $images.Add($rendered)
            Assert-ColorNear ($rendered.GetPixel(32, 32)) $foreground "The $foregroundName artwork on $backgroundName changed color."
            $expectedBackground = $background
            if ($backgroundName -eq 'Transparent') {
                $expectedBackground = if ($foregroundName -eq 'White') { [System.Drawing.Color]::Black } else { [System.Drawing.Color]::White }
            }
            Assert-ColorNear ($rendered.GetPixel(0, 32)) $expectedBackground "The $backgroundName background became the $foregroundName logo color."
        }
    }
    Write-Output 'PASS: six artwork colors on nine backgrounds preserve artwork and distinct backing.'

    # Corners disagreeing, edge artwork and mixed alpha are ambiguous: no trim.
    foreach ($kind in @('DifferentCorners', 'EdgeArtwork', 'MixedAlpha', 'Empty', 'Uniform', 'Tiny')) {
        $dimension = if ($kind -eq 'Tiny') { 4 } else { 100 }
        $fixture = [System.Drawing.Bitmap]::new($dimension, $dimension)
        $images.Add($fixture)
        $graphics = [System.Drawing.Graphics]::FromImage($fixture)
        try {
            $graphics.Clear([System.Drawing.Color]::White)
            if ($kind -eq 'DifferentCorners') {
                $graphics.FillRectangle([System.Drawing.Brushes]::Blue, 50, 0, 50, 100)
            }
            elseif ($kind -eq 'EdgeArtwork') {
                $graphics.FillRectangle([System.Drawing.Brushes]::Red, 0, 45, 70, 10)
            }
            elseif ($kind -eq 'MixedAlpha') {
                $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.FillRectangle([System.Drawing.Brushes]::Transparent, 0, 0, 25, 25)
            }
            elseif ($kind -eq 'Empty') { $graphics.Clear([System.Drawing.Color]::Transparent) }
        }
        finally { $graphics.Dispose() }
        $bounds = Get-UniformContentBounds $fixture
        Assert-True ($bounds -eq [System.Drawing.Rectangle]::new(0, 0, $dimension, $dimension)) "$kind was cropped despite ambiguous or missing artwork."
        $rendered = Read-PngBytes (New-RoundedPngBytes -Source $fixture -Size 16 -RadiusPercent 28 -PaddingPercent 0)
        $images.Add($rendered)
    }
    Write-Output 'PASS: ambiguous borders, blank images and tiny inputs use conservative bounds.'

    foreach ($invalidBounds in @(
        [System.Drawing.Rectangle]::new(-1, 0, 20, 20),
        [System.Drawing.Rectangle]::new(190, 0, 20, 20),
        [System.Drawing.Rectangle]::new(0, 0, -1, 20)
    )) {
        $rejected = $false
        try { $null = New-RoundedPngBytes -Source $square -Size 16 -RadiusPercent 28 -PaddingPercent 0 -ContentBounds $invalidBounds }
        catch { $rejected = $_.Exception.Message -like '*Content bounds*' }
        Assert-True $rejected 'Invalid crop bounds were accepted.'
    }
    Write-Output 'PASS: invalid crop rectangles are rejected before rendering.'

    $source = $square
    if ($EdgeSource) {
        $source = [System.Drawing.Bitmap]::new([System.IO.Path]::GetFullPath($EdgeSource))
        $images.Add($source)
    }
    $bounds = Get-UniformContentBounds $source
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $frames = @(
        foreach ($size in $sizes) {
            $data = New-RoundedPngBytes -Source $source -Size $size -RadiusPercent 28 -PaddingPercent 0 -ContentBounds $bounds
            $frame = Read-PngBytes $data
            $images.Add($frame)
            Assert-True ($frame.Width -eq $size -and $frame.Height -eq $size) "Wrong PNG frame size: $size."
            Assert-True ($frame.GetPixel(0, 0).A -eq 0) "The corner is not transparent at $size."
            if ($EdgeSource) {
                $pixel = $frame.GetPixel(0, [int]($size / 2))
                Assert-True ($pixel.A -eq 255 -and $pixel.R -ge 245 -and $pixel.G -ge 245 -and $pixel.B -ge 245) "Edge artwork reaches the card border at $size."
            }
            [pscustomobject]@{ Size = $size; Data = $data }
        }
    )
    [System.IO.File]::WriteAllBytes($icoPath, (New-IcoBytes $frames))
    Test-IcoFile -Path $icoPath -ExpectedSizes $sizes
    Write-Output 'PASS: all seven PNG frames, rounded alpha and ICO entries are valid.'
}
finally {
    foreach ($image in $images) { $image.Dispose() }
    if ([System.IO.File]::Exists($icoPath)) { [System.IO.File]::Delete($icoPath) }
}
