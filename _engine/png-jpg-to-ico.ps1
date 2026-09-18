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

        $corners = @(
            $probe.GetPixel(0, 0),
            $probe.GetPixel($probeWidth - 1, 0),
            $probe.GetPixel(0, $probeHeight - 1),
            $probe.GetPixel($probeWidth - 1, $probeHeight - 1)
        )

        # 四角全透明 = 透明背景，只看 alpha；否则拿四角颜色当背景色。
        $transparent = $true
        foreach ($corner in $corners) {
            if ($corner.A -ge 16) { $transparent = $false }
        }

        $refR = @()
        $refG = @()
        $refB = @()
        if (-not $transparent) {
            foreach ($corner in $corners) {
                if ($corner.A -ge 200) {
                    $refR += [int]$corner.R
                    $refG += [int]$corner.G
                    $refB += [int]$corner.B
                }
            }
            if ($refR.Count -eq 0) {
                return $whole
            }
        }

        $tolerance = 10
        $refCount = $refR.Count
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
                    for ($c = 0; $c -lt $refCount; $c++) {
                        if ([math]::Abs($pixel.R - $refR[$c]) -le $tolerance -and
                            [math]::Abs($pixel.G - $refG[$c]) -le $tolerance -and
                            [math]::Abs($pixel.B - $refB[$c]) -le $tolerance) {
                            $isBackground = $true
                            break
                        }
                    }
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
        [System.Drawing.Bitmap] $Source,
        [int] $Size,
        [int] $RadiusPercent,
        [int] $PaddingPercent,
        [int] $ContentCenterX = -1,
        [int] $ContentCenterY = -1,
        [int] $ContentSide = 0
    )

    # Supersampling leaves clean alpha edges even at 16x16 and 24x24.
    $supersample = 8
    $workSize = $Size * $supersample
    $padding = [int][math]::Round($workSize * $PaddingPercent / 100.0)
    $contentSize = $workSize - (2 * $padding)
    $radius = [int][math]::Round($contentSize * $RadiusPercent / 100.0)
    $radius = [math]::Min($radius, [int][math]::Floor($contentSize / 2))

    # 取背景色用的采样区域永远取原图中心的正方形，和裁切区域分开：
    # 先裁掉白边再取色的话，主色会变成图案本身的颜色，整个图标就糊成一块。
    $sampleSide = [math]::Min($Source.Width, $Source.Height)
    $sampleX = [int][math]::Floor(($Source.Width - $sampleSide) / 2)
    $sampleY = [int][math]::Floor(($Source.Height - $sampleSide) / 2)

    if ($ContentSide -gt 0) {
        # 先按内容边界决定裁切范围，再以内容中心切正方形，
        # 这样同一批图标的图案大小才一致。
        $side = [math]::Min([math]::Min($Source.Width, $Source.Height), $ContentSide)
        $cropX = [int][math]::Max(0, [math]::Min($Source.Width - $side, $ContentCenterX - [int][math]::Floor($side / 2)))
        $cropY = [int][math]::Max(0, [math]::Min($Source.Height - $side, $ContentCenterY - [int][math]::Floor($side / 2)))
        $cropSide = $side
    }
    else {
        $cropSide = $sampleSide
        $cropX = $sampleX
        $cropY = $sampleY
    }

    # Background colour = the most frequent solid colour of the icon. An icon's
    # border is usually a duller shade of that colour, and any corner patch can
    # end up averaging (or even mostly containing) that dull shade - which then
    # paints the very rim we are trying to remove. The dominant colour cannot be
    # fooled that way.
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
    if ($null -eq $topColor) {
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

    try {
        # First create opaque color data. Transparent pixels in the source are
        # backed by colors sampled from the nearest visible corner pixels.
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

        $destination = [System.Drawing.Rectangle]::new(
            $padding,
            $padding,
            $contentSize,
            $contentSize
        )
        $workGraphics.DrawImage(
            $Source,
            $destination,
            $cropX,
            $cropY,
            $cropSide,
            $cropSide,
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
            [System.Drawing.GraphicsUnit]::Pixel
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
            [System.Drawing.GraphicsUnit]::Pixel
        )

        $output = [System.Drawing.Bitmap]::new(
            $Size,
            $Size,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        # Card colour: the most common colour inside the four corner patches, 8% to 22%
        # of the way in. A logo sits in the middle and along the edges and never reaches
        # a corner, so those patches are pure card body. Voting with exact colours here
        # is what gave the version the user confirmed as good.
        $cornerInner = [math]::Max(3, [int][math]::Round($Size * 0.08))
        $cornerOuter = [math]::Max($cornerInner + 2, [int][math]::Round($Size * 0.22))
        $bandColor = $topColor
        $bandVotes = @{}
        for ($bandY = 0; $bandY -lt $Size; $bandY++) {
            $bandEdgeY = [math]::Min($bandY, $Size - 1 - $bandY)
            if ($bandEdgeY -lt $cornerInner -or $bandEdgeY -gt $cornerOuter) { continue }
            for ($bandX = 0; $bandX -lt $Size; $bandX++) {
                $bandEdgeX = [math]::Min($bandX, $Size - 1 - $bandX)
                if ($bandEdgeX -lt $cornerInner -or $bandEdgeX -gt $cornerOuter) { continue }
                if ($maskFinal.GetPixel($bandX, $bandY).R -lt 128) { continue }
                $bandPixel = $final.GetPixel($bandX, $bandY)
                $bandKey = "$($bandPixel.R),$($bandPixel.G),$($bandPixel.B)"
                if ($bandVotes.ContainsKey($bandKey)) {
                    $bandVotes[$bandKey] = $bandVotes[$bandKey] + 1
                }
                else {
                    $bandVotes[$bandKey] = 1
                }
            }
        }
        $bandBest = 0
        foreach ($bandEntry in $bandVotes.GetEnumerator()) {
            if ($bandEntry.Value -gt $bandBest) {
                $bandBest = $bandEntry.Value
                $bandParts = $bandEntry.Key -split ','
                $bandColor = [System.Drawing.Color]::FromArgb(255, [int]$bandParts[0], [int]$bandParts[1], [int]$bandParts[2])
            }
        }
        $centre = ($Size - 1) / 2.0
        for ($y = 0; $y -lt $Size; $y++) {
            $t = if ($Size -gt 1) { $y / [double]($Size - 1) } else { 0.0 }
            $bgR = [int][math]::Round($topColor.R + ($bottomColor.R - $topColor.R) * $t)
            $bgG = [int][math]::Round($topColor.G + ($bottomColor.G - $topColor.G) * $t)
            $bgB = [int][math]::Round($topColor.B + ($bottomColor.B - $topColor.B) * $t)
            $edgeY = [math]::Min($y, $Size - 1 - $y)
            for ($x = 0; $x -lt $Size; $x++) {
                $color = $final.GetPixel($x, $y)
                $alpha = $maskFinal.GetPixel($x, $y).R
                $red = $color.R
                $green = $color.G
                $blue = $color.B
                # Only the outermost sliver is repainted. A wide band (this used to be
                # 20% of the frame) simply eats the outer edge of any artwork that
                # reaches the border - a full-bleed ring or disc lost its rim and shrank
                # to the middle 60% of the card. 6% is enough to clean a dull or dark
                # rim while leaving the artwork intact.
                $outerBand = [math]::Max(2, [int][math]::Round($Size * 0.06))
                $cornerSpan = [int][math]::Round($Size * 0.06)
                $inBand = $edgeY -lt $outerBand -or $x -lt $outerBand -or ($Size - 1 - $x) -lt $outerBand
                if ($alpha -lt 255 -or $inBand) {
                    # The transparent/anti-aliased edge of the rounded shape, any dark or
                    # dull border, and everything in the corners carries the card colour.
                    # Corners are always repainted: a logo never sits there, so a pale
                    # block left behind by an earlier version cannot survive. Along the
                    # edges a near-white pixel is taken to be the logo and kept.
                    $bandSum = $bandColor.R + $bandColor.G + $bandColor.B
                    $selfSum = $red + $green + $blue
                    $inCorner = (($x -lt $cornerSpan) -or ($x -ge $Size - $cornerSpan)) -and (($y -lt $cornerSpan) -or ($y -ge $Size - $cornerSpan))
                    $isLogo = (-not $inCorner) -and ($selfSum -gt ($bandSum + 12)) -and ($selfSum -gt 720)
                    if (-not $isLogo) {
                        $red = $bandColor.R
                        $green = $bandColor.G
                        $blue = $bandColor.B
                    }
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

        $centerX = -1
        $centerY = -1
        $contentSide = 0
        if ($TrimBorder) {
            $bounds = Get-UniformContentBounds -Source $source
            if ($bounds.Width -lt $source.Width -or $bounds.Height -lt $source.Height) {
                $contentSide = [math]::Min($source.Width, [math]::Min($source.Height, [math]::Max($bounds.Width, $bounds.Height)))
                $centerX = $bounds.X + [int][math]::Floor($bounds.Width / 2)
                $centerY = $bounds.Y + [int][math]::Floor($bounds.Height / 2)
                [Console]::Out.WriteLine("  已裁掉空白边：$($bounds.Width) x $($bounds.Height)（原图 $($source.Width) x $($source.Height)）")
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
                        -ContentCenterX $centerX `
                        -ContentCenterY $centerY `
                        -ContentSide $contentSide
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
