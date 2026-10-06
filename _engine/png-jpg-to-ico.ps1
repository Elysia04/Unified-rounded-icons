#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $InputPath,

    [string] $OutputDir,

    [ValidateRange(0, 50)]
    [int] $RadiusPercent = 28,

    [ValidateRange(0, 20)]
    [int] $PaddingPercent = 0,

    [switch] $TrimBorder,

    [switch] $NoOpenDialog
)

Set-StrictMode -Version Latest
# 被图形界面调用时标准输出是管道，改用 UTF-8 传中文；
# 在 cmd 窗口里直接拖放运行时保持控制台编码，否则窗口里全是乱码。
if ([Console]::IsOutputRedirected) {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
}

# 关掉进度条记录：PowerShell 在标准错误被重定向时会把进度和 Write-Host
# 序列化成一大坨 CLIXML，图形界面读起来全是乱码，这里直接禁掉。
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$IconSizes = @(16, 24, 32, 48, 64, 128, 256)
$SupportedExtensions = @('.png', '.jpg', '.jpeg')
# 本脚本位于 _engine 子文件夹内，工具根目录在它的上一层，
# 输出目录固定为根目录下的“修改图标存放”。
$ToolRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrEmpty($ToolRoot)) { $ToolRoot = $PSScriptRoot }
$DefaultOutputDir = Join-Path $ToolRoot '修改图标存放'

function Get-ExifOrientation {
    param([System.Drawing.Image] $Image)

    try {
        $property = $Image.GetPropertyItem(0x0112)
        return [BitConverter]::ToUInt16($property.Value, 0)
    }
    catch {
        return 1
    }
}

function Apply-ExifOrientation {
    param([System.Drawing.Image] $Image)

    switch (Get-ExifOrientation $Image) {
        2 { $Image.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX) }
        3 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
        4 { $Image.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipY) }
        5 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipX) }
        6 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
        7 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipX) }
        8 { $Image.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
    }
}

function Copy-ToArgbBitmap {
    param([System.Drawing.Image] $Image)

    $copy = [System.Drawing.Bitmap]::new(
        $Image.Width,
        $Image.Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = $null

    try {
        $graphics = [System.Drawing.Graphics]::FromImage($copy)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.DrawImageUnscaled($Image, 0, 0)
        return $copy
    }
    catch {
        $copy.Dispose()
        throw
    }
    finally {
        if ($null -ne $graphics) {
            $graphics.Dispose()
        }
    }
}

function New-RoundedRectanglePath {
    param(
        [int] $X,
        [int] $Y,
        [int] $Width,
        [int] $Height,
        [int] $Radius
    )

    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()

    if ($Radius -le 0) {
        $path.AddRectangle([System.Drawing.Rectangle]::new($X, $Y, $Width, $Height))
        return $path
    }

    $diameter = $Radius * 2
    $right = $X + $Width
    $bottom = $Y + $Height

    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc($right - $diameter, $Y, $diameter, $diameter, 270, 90)
    $path.AddArc($right - $diameter, $bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($X, $bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Get-NearbyCornerColor {
    param(
        [System.Drawing.Bitmap] $Source,
        [int] $CropX,
        [int] $CropY,
        [int] $CropSide,
        [ValidateSet('TopLeft', 'TopRight', 'BottomLeft', 'BottomRight')]
        [string] $Corner
    )

    # Sample a patch that sits a little inside the corner instead of the first
    # opaque pixel: pixels hugging the border are anti-aliased and end up duller
    # than the icon body, so a plain average of the patch drags the background
    # colour down and paints a faint rim. The per-channel median ignores that
    # minority of dull pixels and lands on the real body colour.
    $inset = [math]::Max(2, [int][math]::Round($CropSide * 0.15))
    $patch = [math]::Max(3, [int][math]::Round($CropSide * 0.14))

    switch ($Corner) {
        'TopLeft' {
            $x0 = $CropX + $inset
            $y0 = $CropY + $inset
        }
        'TopRight' {
            $x0 = $CropX + $CropSide - $inset - $patch
            $y0 = $CropY + $inset
        }
        'BottomLeft' {
            $x0 = $CropX + $inset
            $y0 = $CropY + $CropSide - $inset - $patch
        }
        'BottomRight' {
            $x0 = $CropX + $CropSide - $inset - $patch
            $y0 = $CropY + $CropSide - $inset - $patch
        }
    }

    $rValues = [System.Collections.Generic.List[int]]::new()
    $gValues = [System.Collections.Generic.List[int]]::new()
    $bValues = [System.Collections.Generic.List[int]]::new()
    for ($dy = 0; $dy -lt $patch; $dy++) {
        $y = $y0 + $dy
        if ($y -lt $CropY -or $y -ge $CropY + $CropSide) { continue }
        for ($dx = 0; $dx -lt $patch; $dx++) {
            $x = $x0 + $dx
            if ($x -lt $CropX -or $x -ge $CropX + $CropSide) { continue }
            $pixel = $Source.GetPixel($x, $y)
            if ($pixel.A -ge 200) {
                $rValues.Add($pixel.R)
                $gValues.Add($pixel.G)
                $bValues.Add($pixel.B)
            }
        }
    }

    if ($rValues.Count -gt 0) {
        $rArray = $rValues.ToArray()
        $gArray = $gValues.ToArray()
        $bArray = $bValues.ToArray()
        [System.Array]::Sort($rArray)
        [System.Array]::Sort($gArray)
        [System.Array]::Sort($bArray)
        $middle = [int][math]::Floor($rArray.Length / 2)
        return [System.Drawing.Color]::FromArgb(
            255,
            $rArray[$middle],
            $gArray[$middle],
            $bArray[$middle]
        )
    }

    # Fallback for icons that are dark everywhere: walk the diagonal inwards and
    # take the first opaque pixel that is not dark.
    $firstOpaque = $null
    for ($distance = 0; $distance -lt $CropSide; $distance++) {
        switch ($Corner) {
            'TopLeft' {
                $x = $CropX + $distance
                $y = $CropY + $distance
            }
            'TopRight' {
                $x = $CropX + $CropSide - 1 - $distance
                $y = $CropY + $distance
            }
            'BottomLeft' {
                $x = $CropX + $distance
                $y = $CropY + $CropSide - 1 - $distance
            }
            'BottomRight' {
                $x = $CropX + $CropSide - 1 - $distance
                $y = $CropY + $CropSide - 1 - $distance
            }
        }

        $pixel = $Source.GetPixel($x, $y)
        if ($pixel.A -ge 128) {
            if ($null -eq $firstOpaque) {
                $firstOpaque = $pixel
            }
            if ([math]::Max($pixel.R, [math]::Max($pixel.G, $pixel.B)) -ge 64) {
                return [System.Drawing.Color]::FromArgb(255, $pixel.R, $pixel.G, $pixel.B)
            }
        }
    }

    if ($null -ne $firstOpaque) {
        return [System.Drawing.Color]::FromArgb(255, $firstOpaque.R, $firstOpaque.G, $firstOpaque.B)
    }

    $center = $Source.GetPixel(
        $CropX + [int][math]::Floor($CropSide / 2),
        $CropY + [int][math]::Floor($CropSide / 2)
    )
    return [System.Drawing.Color]::FromArgb(255, $center.R, $center.G, $center.B)
}

function Mix-Colors {
    param(
        [System.Drawing.Color] $First,
        [System.Drawing.Color] $Second
    )

    return [System.Drawing.Color]::FromArgb(
        255,
        [int][math]::Round(($First.R + $Second.R) / 2.0),
        [int][math]::Round(($First.G + $Second.G) / 2.0),
        [int][math]::Round(($First.B + $Second.B) / 2.0)
    )
}

function Get-UniformBorderBackground {
    param([System.Drawing.Bitmap] $Source)

    # A corner alone can belong to the artwork. Require agreement around all
    # four edges before treating any color (or transparency) as empty space.
    $reference = $Source.GetPixel(0, 0)
    $transparent = $reference.A -lt 16
    $stepX = [math]::Max(1, [int][math]::Floor($Source.Width / 256))
    $stepY = [math]::Max(1, [int][math]::Floor($Source.Height / 256))
    $samples = [System.Collections.Generic.List[System.Drawing.Color]]::new()
    for ($x = 0; $x -lt $Source.Width; $x += $stepX) {
        $samples.Add($Source.GetPixel($x, 0))
        $samples.Add($Source.GetPixel($x, $Source.Height - 1))
    }
    for ($y = 0; $y -lt $Source.Height; $y += $stepY) {
        $samples.Add($Source.GetPixel(0, $y))
        $samples.Add($Source.GetPixel($Source.Width - 1, $y))
    }
    $samples.Add($Source.GetPixel($Source.Width - 1, $Source.Height - 1))
    foreach ($sample in $samples) {
        if ($transparent) {
            if ($sample.A -ge 16) { return $null }
        }
        elseif ($sample.A -lt 200 -or
            [math]::Abs([int]$sample.R - $reference.R) -gt 10 -or
            [math]::Abs([int]$sample.G - $reference.G) -gt 10 -or
            [math]::Abs([int]$sample.B - $reference.B) -gt 10) {
            return $null
        }
    }
    return [pscustomobject]@{ Transparent = $transparent; Color = $reference }
}

function Get-UniformContentBounds {
    param(
        [System.Drawing.Bitmap] $Source
    )

    # 整图逐像素扫描在 PowerShell 里太慢，先缩到 256 像素再找内容边界，
    # 误差只有几个原始像素，做图标看不出来。
    $limit = 256
    $scale = 1.0
    if ($Source.Width -gt $limit -or $Source.Height -gt $limit) {
        $scale = $limit / [double][math]::Max($Source.Width, $Source.Height)
    }

    $probeWidth = [math]::Max(1, [int][math]::Round($Source.Width * $scale))
    $probeHeight = [math]::Max(1, [int][math]::Round($Source.Height * $scale))
    $whole = [System.Drawing.Rectangle]::new(0, 0, $Source.Width, $Source.Height)
    $background = Get-UniformBorderBackground $Source
    if ($null -eq $background) { return $whole }

    $probe = [System.Drawing.Bitmap]::new(
        $probeWidth,
        $probeHeight,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = $null
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($probe)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage(
            $Source,
            [System.Drawing.Rectangle]::new(0, 0, $probeWidth, $probeHeight),
            0,
            0,
            $Source.Width,
            $Source.Height,
            [System.Drawing.GraphicsUnit]::Pixel
        )

        $transparent = $background.Transparent
        $reference = $background.Color

        $tolerance = 10
        $minX = $probeWidth
        $minY = $probeHeight
        $maxX = -1
        $maxY = -1

        for ($y = 0; $y -lt $probeHeight; $y++) {
            for ($x = 0; $x -lt $probeWidth; $x++) {
                $pixel = $probe.GetPixel($x, $y)
                $isBackground = $false
                if ($transparent) {
                    $isBackground = $pixel.A -lt 16
                }
                else {
                    $isBackground = $pixel.A -lt 16 -or (
                        $pixel.A -ge 200 -and
                        [math]::Abs([int]$pixel.R - $reference.R) -le $tolerance -and
                        [math]::Abs([int]$pixel.G - $reference.G) -le $tolerance -and
                        [math]::Abs([int]$pixel.B - $reference.B) -le $tolerance
                    )
                }

                if (-not $isBackground) {
                    if ($x -lt $minX) { $minX = $x }
                    if ($x -gt $maxX) { $maxX = $x }
                    if ($y -lt $minY) { $minY = $y }
                    if ($y -gt $maxY) { $maxY = $y }
                }
            }
        }

        if ($maxX -lt $minX -or $maxY -lt $minY) {
            return $whole
        }

        $ratioX = $Source.Width / [double]$probeWidth
        $ratioY = $Source.Height / [double]$probeHeight
        $margin = [int][math]::Ceiling([math]::Max($ratioX, $ratioY))

        $left = [math]::Max(0, [int][math]::Floor($minX * $ratioX) - $margin)
        $top = [math]::Max(0, [int][math]::Floor($minY * $ratioY) - $margin)
        $right = [math]::Min($Source.Width, [int][math]::Ceiling(($maxX + 1) * $ratioX) + $margin)
        $bottom = [math]::Min($Source.Height, [int][math]::Ceiling(($maxY + 1) * $ratioY) + $margin)

        # 保险：每边最多只裁 45%，避免误判把主体裁掉。
        $capX = [int][math]::Round($Source.Width * 0.45)
        $capY = [int][math]::Round($Source.Height * 0.45)
        if ($left -gt $capX) { $left = $capX }
        if ($top -gt $capY) { $top = $capY }
        if (($Source.Width - $right) -gt $capX) { $right = $Source.Width - $capX }
        if (($Source.Height - $bottom) -gt $capY) { $bottom = $Source.Height - $capY }

        if (($right - $left) -lt 8 -or ($bottom - $top) -lt 8) {
            return $whole
        }

        return [System.Drawing.Rectangle]::new($left, $top, ($right - $left), ($bottom - $top))
    }
    finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        $probe.Dispose()
    }
}
function New-RoundedPngBytes {
    param(
        [ValidateNotNull()]
        [System.Drawing.Bitmap] $Source,
        [ValidateRange(16, 256)]
        [int] $Size,
        [ValidateRange(0, 50)]
        [int] $RadiusPercent,
        [ValidateRange(0, 20)]
        [int] $PaddingPercent,
        [System.Drawing.Rectangle] $ContentBounds = [System.Drawing.Rectangle]::Empty
    )

    # Supersampling leaves clean alpha edges even at 16x16 and 24x24.
    $supersample = 8
    $workSize = $Size * $supersample
    $padding = [int][math]::Round($workSize * $PaddingPercent / 100.0)
    $contentSize = $workSize - (2 * $padding)
    $radius = [int][math]::Round($contentSize * $RadiusPercent / 100.0)
    $radius = [math]::Min($radius, [int][math]::Floor($contentSize / 2))

    # Keep fallback color sampling separate from the trimmed artwork bounds.
    $sampleSide = [math]::Min($Source.Width, $Source.Height)
    $sampleX = [int][math]::Floor(($Source.Width - $sampleSide) / 2)
    $sampleY = [int][math]::Floor(($Source.Height - $sampleSide) / 2)

    if (-not $ContentBounds.IsEmpty) {
        if ($ContentBounds.Width -le 0 -or $ContentBounds.Height -le 0 -or
            $ContentBounds.X -lt 0 -or $ContentBounds.Y -lt 0 -or
            ([long]$ContentBounds.X + $ContentBounds.Width) -gt $Source.Width -or
            ([long]$ContentBounds.Y + $ContentBounds.Height) -gt $Source.Height) {
            throw 'Content bounds must be positive and lie inside the source image.'
        }
        # Fit the complete artwork with one scale factor. Leave room for the
        # rounded mask; filling the card with trimmed artwork clips its edges.
        $insetRatio = [math]::Max(0.10, ($RadiusPercent / 100.0) * (1 - 1 / [math]::Sqrt(2)) + 1.0 / ($contentSize / $supersample))
        $artworkSize = $contentSize * (1 - 2 * $insetRatio)
        $scale = $artworkSize / [math]::Max($ContentBounds.Width, $ContentBounds.Height)
        $drawWidth = $ContentBounds.Width * $scale
        $drawHeight = $ContentBounds.Height * $scale
        $sourceRect = $ContentBounds
        $destination = [System.Drawing.RectangleF]::new(
            [single]($padding + ($contentSize - $drawWidth) / 2),
            [single]($padding + ($contentSize - $drawHeight) / 2),
            [single]$drawWidth,
            [single]$drawHeight
        )
    }
    else {
        $sourceRect = [System.Drawing.Rectangle]::new($sampleX, $sampleY, $sampleSide, $sampleSide)
        $destination = [System.Drawing.RectangleF]::new($padding, $padding, $contentSize, $contentSize)
    }

    # Prefer the verified border color so a solid logo cannot become its own
    # background. Transparent tiles use their dominant visible color as backing.
    $borderBackground = Get-UniformBorderBackground $Source
    $votes = @{}
    $sampleStep = [math]::Max(1, [int][math]::Floor($sampleSide / 64))
    for ($sy = 0; $sy -lt $sampleSide; $sy += $sampleStep) {
        for ($sx = 0; $sx -lt $sampleSide; $sx += $sampleStep) {
            $sample = $Source.GetPixel($sampleX + $sx, $sampleY + $sy)
            if ($sample.A -lt 200) { continue }
            $key = "$($sample.R),$($sample.G),$($sample.B)"
            if ($votes.ContainsKey($key)) {
                $votes[$key] = $votes[$key] + 1
            }
            else {
                $votes[$key] = 1
            }
        }
    }

    $topColor = $null
    $bestVotes = 0
    foreach ($entry in $votes.GetEnumerator()) {
        if ($entry.Value -gt $bestVotes) {
            $bestVotes = $entry.Value
            $parts = $entry.Key -split ','
            $topColor = [System.Drawing.Color]::FromArgb(255, [int]$parts[0], [int]$parts[1], [int]$parts[2])
        }
    }
    if ($null -ne $borderBackground -and -not $borderBackground.Transparent) {
        $topColor = [System.Drawing.Color]::FromArgb(255, $borderBackground.Color.R, $borderBackground.Color.G, $borderBackground.Color.B)
    }
    elseif ($null -ne $borderBackground -and $borderBackground.Transparent) {
        # An isolated transparent logo has no card color. Use a neutral backing
        # with contrast rather than filling its empty space with the logo color.
        $topColor = if ($null -ne $topColor -and $topColor.R -gt 230 -and $topColor.G -gt 230 -and $topColor.B -gt 230) {
            [System.Drawing.Color]::Black
        }
        else { [System.Drawing.Color]::White }
    }
    elseif ($null -eq $topColor) {
        $topColor = Mix-Colors `
            (Get-NearbyCornerColor $Source $sampleX $sampleY $sampleSide TopLeft) `
            (Get-NearbyCornerColor $Source $sampleX $sampleY $sampleSide TopRight)
    }
    $bottomColor = $topColor

    $work = [System.Drawing.Bitmap]::new(
        $workSize,
        $workSize,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $workGraphics = $null
    $gradient = $null
    $path = $null
    $maskWork = $null
    $maskGraphics = $null
    $maskBrush = $null
    $final = $null
    $finalGraphics = $null
    $maskFinal = $null
    $maskFinalGraphics = $null
    $output = $null
    $stream = $null
    $imageAttributes = $null

    try {
        # Bicubic sampling must not read transparent black beyond the bitmap.
        $imageAttributes = [System.Drawing.Imaging.ImageAttributes]::new()
        $imageAttributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        # Back source transparency with the chosen card color before masking.
        $workGraphics = [System.Drawing.Graphics]::FromImage($work)
        $workGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $workGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $workGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $workGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $workGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gradient = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            [System.Drawing.Rectangle]::new(0, 0, $workSize, $workSize),
            $topColor,
            $bottomColor,
            [single]90
        )
        $workGraphics.FillRectangle($gradient, 0, 0, $workSize, $workSize)

        $workGraphics.DrawImage(
            $Source,
            $destination,
            [System.Drawing.RectangleF]::new($sourceRect.X, $sourceRect.Y, $sourceRect.Width, $sourceRect.Height),
            [System.Drawing.GraphicsUnit]::Pixel
        )

        # Build the rounded alpha separately so the transparent edge keeps
        # nearby RGB data instead of transparent black.
        $path = New-RoundedRectanglePath -X $padding -Y $padding `
            -Width $contentSize -Height $contentSize -Radius $radius
        $maskWork = [System.Drawing.Bitmap]::new(
            $workSize,
            $workSize,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $maskGraphics = [System.Drawing.Graphics]::FromImage($maskWork)
        $maskGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $maskGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $maskGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $maskGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $maskGraphics.Clear([System.Drawing.Color]::Black)
        $maskBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
        $maskGraphics.FillPath($maskBrush, $path)

        $final = [System.Drawing.Bitmap]::new(
            $Size,
            $Size,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $finalGraphics = [System.Drawing.Graphics]::FromImage($final)
        $finalGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $finalGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $finalGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $finalGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $finalGraphics.DrawImage(
            $work,
            [System.Drawing.Rectangle]::new(0, 0, $Size, $Size),
            0,
            0,
            $workSize,
            $workSize,
            [System.Drawing.GraphicsUnit]::Pixel,
            $imageAttributes
        )

        $maskFinal = [System.Drawing.Bitmap]::new(
            $Size,
            $Size,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $maskFinalGraphics = [System.Drawing.Graphics]::FromImage($maskFinal)
        $maskFinalGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $maskFinalGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $maskFinalGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $maskFinalGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $maskFinalGraphics.DrawImage(
            $maskWork,
            [System.Drawing.Rectangle]::new(0, 0, $Size, $Size),
            0,
            0,
            $workSize,
            $workSize,
            [System.Drawing.GraphicsUnit]::Pixel,
            $imageAttributes
        )

        $output = [System.Drawing.Bitmap]::new(
            $Size,
            $Size,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        for ($y = 0; $y -lt $Size; $y++) {
            for ($x = 0; $x -lt $Size; $x++) {
                $color = $final.GetPixel($x, $y)
                $alpha = $maskFinal.GetPixel($x, $y).R
                $red = $color.R
                $green = $color.G
                $blue = $color.B
                # Source transparency was composited over the background above.
                # Keep visible RGB intact, including colored artwork at the edge.
                if ($alpha -eq 0) {
                    $red = $topColor.R
                    $green = $topColor.G
                    $blue = $topColor.B
                }
                $output.SetPixel(
                    $x,
                    $y,
                    [System.Drawing.Color]::FromArgb($alpha, $red, $green, $blue)
                )
            }
        }

        $stream = [System.IO.MemoryStream]::new()
        $output.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return ,([byte[]]$stream.ToArray())
    }
    finally {
        if ($null -ne $imageAttributes) { $imageAttributes.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $output) { $output.Dispose() }
        if ($null -ne $maskFinalGraphics) { $maskFinalGraphics.Dispose() }
        if ($null -ne $maskFinal) { $maskFinal.Dispose() }
        if ($null -ne $finalGraphics) { $finalGraphics.Dispose() }
        if ($null -ne $final) { $final.Dispose() }
        if ($null -ne $maskBrush) { $maskBrush.Dispose() }
        if ($null -ne $maskGraphics) { $maskGraphics.Dispose() }
        if ($null -ne $maskWork) { $maskWork.Dispose() }
        if ($null -ne $path) { $path.Dispose() }
        if ($null -ne $gradient) { $gradient.Dispose() }
        if ($null -ne $workGraphics) { $workGraphics.Dispose() }
        if ($null -ne $work) { $work.Dispose() }
    }
}

function New-IcoBytes {
    param([object[]] $Frames)

    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)

    try {
        $writer.Write([UInt16]0) # reserved
        $writer.Write([UInt16]1) # icon type
        $writer.Write([UInt16]$Frames.Count)

        $offset = 6 + (16 * $Frames.Count)
        foreach ($frame in $Frames) {
            $dimension = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
            $writer.Write([byte]$dimension)
            $writer.Write([byte]$dimension)
            $writer.Write([byte]0) # palette colors
            $writer.Write([byte]0) # reserved
            $writer.Write([UInt16]1) # color planes
            $writer.Write([UInt16]32) # bits per pixel
            $writer.Write([UInt32]$frame.Data.Length)
            $writer.Write([UInt32]$offset)
            $offset += $frame.Data.Length
        }

        foreach ($frame in $Frames) {
            $writer.Write($frame.Data)
        }

        $writer.Flush()
        return ,([byte[]]$stream.ToArray())
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Test-IcoFile {
    param(
        [string] $Path,
        [int[]] $ExpectedSizes
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 6) {
        throw "生成的 ICO 文件太小。"
    }

    $type = [BitConverter]::ToUInt16($bytes, 2)
    $count = [BitConverter]::ToUInt16($bytes, 4)
    if ($type -ne 1 -or $count -ne $ExpectedSizes.Count) {
        throw "ICO 头校验失败。"
    }

    for ($i = 0; $i -lt $ExpectedSizes.Count; $i++) {
        $entryOffset = 6 + (16 * $i)
        $width = if ($bytes[$entryOffset] -eq 0) { 256 } else { $bytes[$entryOffset] }
        $height = if ($bytes[$entryOffset + 1] -eq 0) { 256 } else { $bytes[$entryOffset + 1] }
        if ($width -ne $ExpectedSizes[$i] -or $height -ne $ExpectedSizes[$i]) {
            throw "ICO 尺寸校验失败：$width x $height。"
        }

        $imageOffset = [int][BitConverter]::ToUInt32($bytes, $entryOffset + 12)
        $imageSize = [int][BitConverter]::ToUInt32($bytes, $entryOffset + 8)
        if ($imageOffset -lt 0 -or $imageOffset + 8 -gt $bytes.Length -or $imageOffset + $imageSize -gt $bytes.Length) {
            throw "ICO 图层偏移校验失败。"
        }

        $pngSignature = 137, 80, 78, 71, 13, 10, 26, 10
        for ($j = 0; $j -lt 8; $j++) {
            if ($bytes[$imageOffset + $j] -ne $pngSignature[$j]) {
                throw "ICO 图层不是 PNG 数据。"
            }
        }
    }
}

function Select-InputFiles {
    if ($NoOpenDialog) {
        return @()
    }

    Add-Type -AssemblyName System.Windows.Forms
    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    try {
        $dialog.Title = '选择要转换的 PNG/JPG 图片'
        $dialog.Filter = '图片文件 (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg'
        $dialog.Multiselect = $true
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return @($dialog.FileNames)
        }
        return @()
    }
    finally {
        $dialog.Dispose()
    }
}

if (-not $InputPath -or $InputPath.Count -eq 0) {
    $InputPath = Select-InputFiles
}

if (-not $InputPath -or $InputPath.Count -eq 0) {
    [Console]::Out.WriteLine('未选择图片。')
    exit 0
}

$files = @()
foreach ($path in $InputPath) {
    try {
        $resolved = Resolve-Path -LiteralPath $path
        $item = Get-Item -LiteralPath $resolved.Path
        if (-not $item.PSIsContainer) {
            $files += $item
        }
    }
    catch {
        Write-Warning "找不到文件：$path"
    }
}

if ($files.Count -eq 0) {
    throw '没有可转换的图片文件。'
}

$converted = 0
$index = 0
foreach ($file in $files) {
    $index++
    $extension = $file.Extension.ToLowerInvariant()
    if ($SupportedExtensions -notcontains $extension) {
        [Console]::Out.WriteLine("跳过不支持的文件：$($file.Name)")
        continue
    }

    $sourceFile = $null
    $source = $null
    try {
        $sourceFile = [System.Drawing.Image]::FromFile($file.FullName)
        Apply-ExifOrientation $sourceFile
        $source = Copy-ToArgbBitmap $sourceFile

        [Console]::Out.WriteLine("正在处理：($index/$($files.Count)) $($file.Name)")

        $contentBounds = [System.Drawing.Rectangle]::Empty
        if ($TrimBorder) {
            $bounds = Get-UniformContentBounds -Source $source
            if ($bounds.Width -lt $source.Width -or $bounds.Height -lt $source.Height) {
                $contentBounds = $bounds
                [Console]::Out.WriteLine("  已裁掉空白边：$($bounds.Width) x $($bounds.Height)（原图 $($source.Width) x $($source.Height)）")
            }
            elseif ($source.Width -ne $source.Height) {
                # Ambiguous borders still need containment for rectangular inputs.
                $contentBounds = $bounds
            }
        }

        $frames = @(
            foreach ($size in $IconSizes) {
                [pscustomobject]@{
                    Size = $size
                    Data = New-RoundedPngBytes `
                        -Source $source `
                        -Size $size `
                        -RadiusPercent $RadiusPercent `
                        -PaddingPercent $PaddingPercent `
                        -ContentBounds $contentBounds
                }
            }
        )

        $targetDirectory = if ($OutputDir) {
            [System.IO.Path]::GetFullPath($OutputDir)
        }
        else {
            $DefaultOutputDir
        }
        if (-not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }

        $outputPath = Join-Path $targetDirectory "$($file.BaseName).ico"
        [System.IO.File]::WriteAllBytes($outputPath, (New-IcoBytes $frames))
        Test-IcoFile -Path $outputPath -ExpectedSizes $IconSizes

        [Console]::Out.WriteLine("已生成：$outputPath")
        $converted++
    }
    catch {
        [Console]::Error.WriteLine("转换失败（$($file.FullName)）：$($_.Exception.Message)")
    }
    finally {
        if ($null -ne $source) { $source.Dispose() }
        if ($null -ne $sourceFile) { $sourceFile.Dispose() }
    }
}

if ($converted -eq 0) {
    exit 1
}
