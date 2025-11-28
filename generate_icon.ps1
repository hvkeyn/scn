# Generate SCN icon
# This script creates a simple SCN icon for Windows

Add-Type -AssemblyName System.Drawing

$sizes = @(16, 32, 48, 256)
$outputDir = "scn\windows\runner\resources"

# Create icon bitmap for each size
function Create-SCNBitmap {
    param([int]$size)
    
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    
    # Background gradient (blue)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb(255, 33, 150, 243),  # #2196F3
        [System.Drawing.Color]::FromArgb(255, 13, 71, 161),   # #0D47A1
        [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal
    )
    
    # Draw rounded rectangle
    $radius = [int]($size * 0.2)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $radius * 2, $radius * 2, 180, 90)
    $path.AddArc($size - $radius * 2, 0, $radius * 2, $radius * 2, 270, 90)
    $path.AddArc($size - $radius * 2, $size - $radius * 2, $radius * 2, $radius * 2, 0, 90)
    $path.AddArc(0, $size - $radius * 2, $radius * 2, $radius * 2, 90, 90)
    $path.CloseFigure()
    
    $graphics.FillPath($brush, $path)
    
    # Draw SCN text - use smaller font to fit
    $fontSize = [int]($size * 0.28)
    if ($fontSize -lt 5) { $fontSize = 5 }
    $font = New-Object System.Drawing.Font("Arial", $fontSize, [System.Drawing.FontStyle]::Bold)
    $textBrush = [System.Drawing.Brushes]::White
    
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    
    $textRect = New-Object System.Drawing.RectangleF(0, 0, $size, $size)
    $graphics.DrawString("SCN", $font, $textBrush, $textRect, $format)
    
    $graphics.Dispose()
    $brush.Dispose()
    $font.Dispose()
    
    return $bitmap
}

# Create multi-size ICO file
function Create-ICO {
    param(
        [string]$outputPath,
        [System.Drawing.Bitmap[]]$bitmaps
    )
    
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    
    # ICO header
    $bw.Write([Int16]0)        # Reserved
    $bw.Write([Int16]1)        # Type (1 = ICO)
    $bw.Write([Int16]$bitmaps.Count)  # Number of images
    
    $imageDataOffset = 6 + ($bitmaps.Count * 16)  # Header + directory entries
    $imageDataList = @()
    
    # Write directory entries
    foreach ($bmp in $bitmaps) {
        $pngStream = New-Object System.IO.MemoryStream
        $bmp.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngData = $pngStream.ToArray()
        $imageDataList += ,$pngData
        
        $width = if ($bmp.Width -eq 256) { 0 } else { $bmp.Width }
        $height = if ($bmp.Height -eq 256) { 0 } else { $bmp.Height }
        
        $bw.Write([Byte]$width)      # Width
        $bw.Write([Byte]$height)     # Height
        $bw.Write([Byte]0)           # Color palette
        $bw.Write([Byte]0)           # Reserved
        $bw.Write([Int16]1)          # Color planes
        $bw.Write([Int16]32)         # Bits per pixel
        $bw.Write([Int32]$pngData.Length)  # Image size
        $bw.Write([Int32]$imageDataOffset) # Offset
        
        $imageDataOffset += $pngData.Length
        $pngStream.Dispose()
    }
    
    # Write image data
    foreach ($data in $imageDataList) {
        $bw.Write($data)
    }
    
    # Save to file
    $bytes = $ms.ToArray()
    [System.IO.File]::WriteAllBytes($outputPath, $bytes)
    
    $bw.Dispose()
    $ms.Dispose()
}

Write-Host "Generating SCN icon..." -ForegroundColor Cyan

# Create bitmaps for each size
$bitmaps = @()
foreach ($size in $sizes) {
    Write-Host "  Creating ${size}x${size}..."
    $bitmaps += Create-SCNBitmap -size $size
}

# Create ICO file
$icoPath = Join-Path $PSScriptRoot "$outputDir\app_icon.ico"
Create-ICO -outputPath $icoPath -bitmaps $bitmaps

Write-Host "Icon saved to: $icoPath" -ForegroundColor Green

# Cleanup
foreach ($bmp in $bitmaps) {
    $bmp.Dispose()
}

Write-Host "Done!" -ForegroundColor Green

