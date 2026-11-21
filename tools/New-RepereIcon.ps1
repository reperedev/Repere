# Draws Repère's icon and writes it as src\compass.png (1024 px: the title bar's logo, and the windows' icon) and
# src\compass.ico (16 to 256 px: the taskbar, Alt+Tab, and what a pinned Repère shows). A doodle, as with a marker: a
# tile of Repère's accent, a little crooked, with an inky outline, and a compass sketched on it, its needle's north
# half coral. The wobble comes from a fixed seed, so the icon comes out the same each time. Each size is drawn for
# itself, not scaled down from the large one: at 24 px and less the ring is left out, the needle is wider and the lines
# are thicker, so the icon still reads.
#
#   .\tools\New-RepereIcon.ps1
[CmdletBinding()]
param(
    # Where compass.png and compass.ico go.
    [string]$OutDir = (Join-Path $PSScriptRoot '..\src')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, WindowsBase

function Get-IconBrush([string]$Hex) { [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString($Hex)) }

function Get-IconPen([string]$Hex, [double]$Thickness) {
    # A marker's line: round at its ends and at its corners.
    $pen = [System.Windows.Media.Pen]::new((Get-IconBrush $Hex), $Thickness)
    $pen.StartLineCap = $pen.EndLineCap = 'Round'
    $pen.LineJoin = 'Round'
    $pen
}

function Get-CirclePoint([double]$X, [double]$Y, [double]$Radius, [int]$Count, [double]$Start = 0, [double]$Sweep = 360) {
    # $Count + 1 points along an arc, from $Start degrees over $Sweep (0 is east, clockwise).
    [System.Windows.Point[]]@(for ($i = 0; $i -le $Count; $i++) {
            $angle = ($Start + $Sweep * $i / $Count) * [Math]::PI / 180
            [System.Windows.Point]::new($X + $Radius * [Math]::Cos($angle), $Y + $Radius * [Math]::Sin($angle))
        })
}

function Get-RoundRectPoint([double]$X, [double]$Y, [double]$Width, [double]$Height, [double]$Radius) {
    # A rounded square's outline as points, clockwise from the top right corner, closed.
    $corners = @(, @(($X + $Width - $Radius), ($Y + $Radius), -90)) + @(, @(($X + $Width - $Radius), ($Y + $Height - $Radius), 0)) +
        @(, @(($X + $Radius), ($Y + $Height - $Radius), 90)) + @(, @(($X + $Radius), ($Y + $Radius), 180))
    $points = @(foreach ($corner in $corners) { Get-CirclePoint $corner[0] $corner[1] $Radius 6 $corner[2] 90 })
    [System.Windows.Point[]]($points + $points[0])
}

function Get-WobblyGeometry([System.Windows.Point[]]$Point, [double]$Amount, [System.Random]$Random, [switch]$Open) {
    # A shape traced by hand: each edge cut into short steps, each step nudged by up to $Amount and its corners barely,
    # then drawn straight from step to step, so the corners stay corners and the edges waver.
    $steps = [System.Collections.Generic.List[System.Windows.Point]]::new()
    for ($i = 0; $i -lt $Point.Count - 1; $i++) {
        $a, $b = $Point[$i], $Point[$i + 1]
        $count = [Math]::Max(1, [int]([Math]::Sqrt(($b.X - $a.X) * ($b.X - $a.X) + ($b.Y - $a.Y) * ($b.Y - $a.Y)) / 70))
        for ($k = 0; $k -lt $count; $k++) {
            $nudge = if ($k -eq 0) { $Amount * 0.3 } else { $Amount }
            $steps.Add([System.Windows.Point]::new($a.X + ($b.X - $a.X) * $k / $count + ($Random.NextDouble() - 0.5) * 2 * $nudge,
                    $a.Y + ($b.Y - $a.Y) * $k / $count + ($Random.NextDouble() - 0.5) * 2 * $nudge))
        }
    }
    if ($Open) { $steps.Add($Point[-1]) }
    $geometry = [System.Windows.Media.StreamGeometry]::new()
    $draw = $geometry.Open()
    $draw.BeginFigure($steps[0], $true, -not $Open)
    $draw.PolyLineTo([System.Windows.Point[]]@($steps | Select-Object -Skip 1), $true, $true)
    $draw.Close()
    $geometry
}

function New-IconBitmap([int]$Size) {
    # The icon at $Size pixels, drawn on a 1024 grid.
    $small = $Size -le 24
    $random = [System.Random]::new(7)
    $ink = '#2B1A6E'
    $visual = [System.Windows.Media.DrawingVisual]::new()
    $context = $visual.RenderOpen()
    # Drawn 10 % larger than the grid's 1024 from its center: the tile, its outline and its wobble then reach about 6 px
    # from the edges, as close as the other apps' icons in the taskbar, rather than leaving a wide margin.
    $scale = $Size / 1024 * 1.1
    $context.PushTransform([System.Windows.Media.MatrixTransform]::new($scale, 0, 0, $scale, $Size / 2 - 512 * $scale, $Size / 2 - 512 * $scale))

    # The tile, Repère's accent (#6A48F2), turned a little; small, it wavers less, so it doesn't look ragged.
    $context.PushTransform([System.Windows.Media.RotateTransform]::new(-4, 512, 512))
    $wobble = if ($small) { 5 } else { 14 }
    $outline = if ($small) { 56 } else { 34 }
    $context.DrawGeometry((Get-IconBrush '#6A48F2'), (Get-IconPen $ink $outline), (Get-WobblyGeometry (Get-RoundRectPoint 90 90 844 844 200) $wobble $random))
    $context.Pop()

    # The ring, open at the top, as a quick stroke leaves it.
    if (-not $small) {
        $context.DrawGeometry($null, (Get-IconPen '#FFFFFF' 30), (Get-WobblyGeometry (Get-CirclePoint 512 520 300 40 -80 345) 12 $random -Open))
    }

    # The needle, toward the northeast: its north half coral, its south half white, both outlined in ink.
    $length = if ($small) { 380 } else { 280 }
    $width = if ($small) { 140 } else { 100 }
    $line = if ($small) { 44 } else { 26 }
    $context.PushTransform([System.Windows.Media.RotateTransform]::new(28, 512, 520))
    foreach ($half in @(@{ Tip = 520 + $length; Fill = '#FFFFFF' }, @{ Tip = 520 - $length; Fill = '#FF7A6B' })) {
        $points = [System.Windows.Point[]]@([System.Windows.Point]::new(512, $half.Tip), [System.Windows.Point]::new(512 + $width, 520),
            [System.Windows.Point]::new(512 - $width, 520), [System.Windows.Point]::new(512, $half.Tip))
        $context.DrawGeometry((Get-IconBrush $half.Fill), (Get-IconPen $ink $line), (Get-WobblyGeometry $points 8 $random))
    }
    $context.Pop()
    $context.DrawEllipse((Get-IconBrush $ink), $null, [System.Windows.Point]::new(512, 520), 36, 36)
    $context.Pop()
    $context.Close()

    $bitmap = [System.Windows.Media.Imaging.RenderTargetBitmap]::new($Size, $Size, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $bitmap
}

function ConvertTo-PngByte($Bitmap) {
    $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($Bitmap))
    $stream = [System.IO.MemoryStream]::new()
    $encoder.Save($stream)
    # Whole: not unrolled into its bytes.
    , $stream.ToArray()
}

$OutDir = (Resolve-Path $OutDir).Path
[System.IO.File]::WriteAllBytes((Join-Path $OutDir 'compass.png'), (ConvertTo-PngByte (New-IconBitmap 1024)))

# The .ico: one PNG per size, as Windows reads them since Vista. Its header, then an entry per size (a width and a
# height of 0 mean 256), then the images.
$sizes = 16, 20, 24, 32, 40, 48, 64, 256
$images = [System.Collections.Generic.List[byte[]]]::new()
foreach ($size in $sizes) { $images.Add((ConvertTo-PngByte (New-IconBitmap $size))) }
$ico = [System.IO.MemoryStream]::new()
$writer = [System.IO.BinaryWriter]::new($ico)
$writer.Write([uint16]0)
$writer.Write([uint16]1)
$writer.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $side = [byte]($sizes[$i] % 256)
    $writer.Write($side)
    $writer.Write($side)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]32)
    $writer.Write([uint32]$images[$i].Length)
    $writer.Write([uint32]$offset)
    $offset += $images[$i].Length
}
foreach ($image in $images) { $writer.Write($image) }
$writer.Flush()
[System.IO.File]::WriteAllBytes((Join-Path $OutDir 'compass.ico'), $ico.ToArray())
Write-Host "$(Join-Path $OutDir 'compass.png')"
Write-Host "$(Join-Path $OutDir 'compass.ico') ($($sizes -join ', ') px)"
