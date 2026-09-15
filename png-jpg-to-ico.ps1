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

    [switch] $NoOpenDialog
)

Set-StrictMode -Version Latest
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

function New-RoundedPngBytes {
    param(
        [System.Drawing.Bitmap] $Source,
        [int] $Size,
        [int] $RadiusPercent,
        [int] $PaddingPercent
    )

    # Supersampling leaves clean alpha edges even at 16x16 and 24x24.
    $supersample = 8
    $workSize = $Size * $supersample
    $padding = [int][math]::Round($workSize * $PaddingPercent / 100.0)
    $contentSize = $workSize - (2 * $padding)
    $radius = [int][math]::Round($contentSize * $RadiusPercent / 100.0)
    $radius = [math]::Min($radius, [int][math]::Floor($contentSize / 2))

    $cropSide = [math]::Min($Source.Width, $Source.Height)
    $cropX = [int][math]::Floor(($Source.Width - $cropSide) / 2)
    $cropY = [int][math]::Floor(($Source.Height - $cropSide) / 2)

    # Background colour = the most frequent solid colour of the icon. An icon's
    # border is usually a duller shade of that colour, and any corner patch can
    # end up averaging (or even mostly containing) that dull shade - which then
    # paints the very rim we are trying to remove. The dominant colour cannot be
    # fooled that way.
    $votes = @{}
    $sampleStep = [math]::Max(1, [int][math]::Floor($cropSide / 64))
    for ($sy = 0; $sy -lt $cropSide; $sy += $sampleStep) {
        for ($sx = 0; $sx -lt $cropSide; $sx += $sampleStep) {
            $sample = $Source.GetPixel($cropX + $sx, $cropY + $sy)
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
            (Get-NearbyCornerColor $Source $cropX $cropY $cropSide TopLeft) `
            (Get-NearbyCornerColor $Source $cropX $cropY $cropSide TopRight)
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
    Write-Host '未选择图片。'
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
foreach ($file in $files) {
    $extension = $file.Extension.ToLowerInvariant()
    if ($SupportedExtensions -notcontains $extension) {
        Write-Warning "跳过不支持的文件：$($file.Name)"
        continue
    }

    $sourceFile = $null
    $source = $null
    try {
        $sourceFile = [System.Drawing.Image]::FromFile($file.FullName)
        Apply-ExifOrientation $sourceFile
        $source = Copy-ToArgbBitmap $sourceFile

        $frames = @(
            foreach ($size in $IconSizes) {
                [pscustomobject]@{
                    Size = $size
                    Data = New-RoundedPngBytes `
                        -Source $source `
                        -Size $size `
                        -RadiusPercent $RadiusPercent `
                        -PaddingPercent $PaddingPercent
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

        Write-Host "已生成：$outputPath"
        $converted++
    }
    catch {
        Write-Error "转换失败（$($file.FullName)）：$($_.Exception.Message)"
    }
    finally {
        if ($null -ne $source) { $source.Dispose() }
        if ($null -ne $sourceFile) { $sourceFile.Dispose() }
    }
}

if ($converted -eq 0) {
    exit 1
}
