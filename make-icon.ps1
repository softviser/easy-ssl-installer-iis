# EasySslInstaller.ico üretir: koyu mavi yuvarlak kare üzerinde beyaz kilit. Harici araç gerekmez.
Add-Type -AssemblyName System.Drawing

function Draw-Lock([int]$s) {
    $bmp = New-Object Drawing.Bitmap $s, $s
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.Clear([Drawing.Color]::Transparent)
    $u = $s / 32.0                                   # 32 birimlik ızgara
    # arka plan
    $bg = New-Object Drawing.Drawing2D.GraphicsPath
    $r = 7 * $u; $w = $s - 1
    $bg.AddArc(0, 0, $r, $r, 180, 90); $bg.AddArc($w - $r, 0, $r, $r, 270, 90)
    $bg.AddArc($w - $r, $w - $r, $r, $r, 0, 90); $bg.AddArc(0, $w - $r, $r, $r, 90, 90); $bg.CloseFigure()
    $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(0x1F, 0x4E, 0x8C))), $bg)
    # kilit kolu
    $pen = New-Object Drawing.Pen ([Drawing.Color]::White), (3.2 * $u); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $g.DrawArc($pen, 10 * $u, 5 * $u, 12 * $u, 12 * $u, 180, 180)
    $g.DrawLine($pen, 10 * $u, 11 * $u, 10 * $u, 14 * $u); $g.DrawLine($pen, 22 * $u, 11 * $u, 22 * $u, 14 * $u)
    # kilit gövdesi
    $body = New-Object Drawing.Drawing2D.GraphicsPath
    $bx = 6 * $u; $by = 13 * $u; $bw = 20 * $u; $bh = 14 * $u; $br = 3 * $u
    $body.AddArc($bx, $by, $br, $br, 180, 90); $body.AddArc($bx + $bw - $br, $by, $br, $br, 270, 90)
    $body.AddArc($bx + $bw - $br, $by + $bh - $br, $br, $br, 0, 90); $body.AddArc($bx, $by + $bh - $br, $br, $br, 90, 90); $body.CloseFigure()
    $g.FillPath([Drawing.Brushes]::White, $body)
    # anahtar deliği
    $kb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(0x1F, 0x4E, 0x8C))
    $g.FillEllipse($kb, 14 * $u, 16.5 * $u, 4 * $u, 4 * $u)
    $g.FillRectangle($kb, 15.2 * $u, 19 * $u, 1.6 * $u, 4.5 * $u)
    $g.Dispose(); $bmp
}

# 32bpp DIB girdisi (BITMAPINFOHEADER + BGRA satırlar alttan üste + boş AND maskesi). .NET Icon sınıfı PNG girdilerini
# küçük boyutlarda okuyamadığından 256 dışındakiler DIB yazılır.
function To-Dib([Drawing.Bitmap]$b) {
    $s = $b.Width; $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
    $w.Write([uint32]40); $w.Write([int32]$s); $w.Write([int32]($s * 2)); $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]0)
    $w.Write([uint32]($s * $s * 4)); $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
    for ($y = $s - 1; $y -ge 0; $y--) { for ($x = 0; $x -lt $s; $x++) { $w.Write([int32]$b.GetPixel($x, $y).ToArgb()) } }
    $w.Write((New-Object byte[] ([Math]::Ceiling($s / 32) * 4 * $s)))
    ,$ms.ToArray()   # virgül şart: yoksa PowerShell diziyi bayt bayt açar
}

# ICO: 6 bayt başlık + 16 bayt/girdi dizin + görüntü verileri
$sizes = 16, 24, 32, 48, 64, 256
$pngs = foreach ($s in $sizes) {
    $b = Draw-Lock $s
    if ($s -ge 256) { $ms = New-Object IO.MemoryStream; $b.Save($ms, [Drawing.Imaging.ImageFormat]::Png); ,$ms.ToArray() } else { ,(To-Dib $b) }
}
$out = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter $out
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s }))); $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset); $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
[IO.File]::WriteAllBytes("$PSScriptRoot\EasySslInstaller.ico", $out.ToArray())
Get-Item "$PSScriptRoot\EasySslInstaller.ico" | Select-Object Name, Length
