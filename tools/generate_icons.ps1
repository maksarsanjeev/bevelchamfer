# Copyright 2026 B&A community. Licensed under Apache License 2.0.
# PNG-фолбэки той же геометрии, что у SVG-иконки.
Add-Type -AssemblyName System.Drawing
$icons = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\bevelchamfer\icons'
foreach ($size in @(16,24)) {
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.ScaleTransform($size / 24.0, $size / 24.0)
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#3C3C3C'), 1.1)
    $shapes = @(
        @{color='#F2F4F6'; points=@(3,7.5,3,17,12,21.5,21,17,21,7.5)},
        @{color='#FFFFFF'; points=@(3,7.5,8,5,16,5,21,7.5,12,12)},
        @{color='#4A90D9'; points=@(8,5,11,2.5,19,2.5,16,5)}
    )
    foreach ($shape in $shapes) {
        $points = @()
        for ($i=0; $i -lt $shape.points.Count; $i+=2) {
            $points += New-Object System.Drawing.PointF([single]$shape.points[$i], [single]$shape.points[$i+1])
        }
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($shape.color))
        $graphics.FillPolygon($brush, [System.Drawing.PointF[]]$points)
        $graphics.DrawPolygon($pen, [System.Drawing.PointF[]]$points)
        $brush.Dispose()
    }
    $graphics.DrawLine($pen,12,12,12,21.5)
    $graphics.DrawLine($pen,19,2.5,21,7.5)
    $graphics.DrawLine($pen,11,2.5,3,7.5)
    $bitmap.Save((Join-Path $icons "chamfer_$size.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $pen.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}
