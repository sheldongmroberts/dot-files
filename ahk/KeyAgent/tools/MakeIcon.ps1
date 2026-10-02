# Draws KeyAgent.ico: a dark keyboard with light keys and a yellow layer key, matching the
# editor's colours. Sizes 16-48 are stored as bitmaps, 256 as PNG (the usual .ico layout).
#   powershell -ExecutionPolicy Bypass -File tools\MakeIcon.ps1 [-Preview preview.png]
param([string]$Out = (Join-Path $PSScriptRoot "..\KeyAgent.ico"), [string]$Preview = "")

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.IO; using System.Drawing; using System.Drawing.Imaging;
public static class IcoWriter {
    public static void Write(string path, Bitmap[] images) {
        var data = new byte[images.Length][];
        for (int i = 0; i < images.Length; i++)
            data[i] = images[i].Width >= 256 ? Png(images[i]) : Dib(images[i]);
        using (var w = new BinaryWriter(File.Create(path))) {
            w.Write((short)0); w.Write((short)1); w.Write((short)images.Length);
            int offset = 6 + 16 * images.Length;
            for (int i = 0; i < images.Length; i++) {
                int s = images[i].Width;
                w.Write((byte)(s >= 256 ? 0 : s)); w.Write((byte)(s >= 256 ? 0 : s));
                w.Write((byte)0); w.Write((byte)0); w.Write((short)1); w.Write((short)32);
                w.Write(data[i].Length); w.Write(offset);
                offset += data[i].Length;
            }
            foreach (var d in data) w.Write(d);
        }
    }
    static byte[] Png(Bitmap b) {
        using (var ms = new MemoryStream()) { b.Save(ms, ImageFormat.Png); return ms.ToArray(); }
    }
    static byte[] Dib(Bitmap b) {
        int s = b.Width, maskStride = ((s + 31) / 32) * 4;
        using (var ms = new MemoryStream()) using (var w = new BinaryWriter(ms)) {
            w.Write(40); w.Write(s); w.Write(s * 2); w.Write((short)1); w.Write((short)32);
            w.Write(0); w.Write(s * s * 4 + maskStride * s); w.Write(0); w.Write(0); w.Write(0); w.Write(0);
            for (int y = s - 1; y >= 0; y--)
                for (int x = 0; x < s; x++) { var c = b.GetPixel(x, y); w.Write(c.B); w.Write(c.G); w.Write(c.R); w.Write(c.A); }
            for (int y = s - 1; y >= 0; y--) {
                var row = new byte[maskStride];
                for (int x = 0; x < s; x++) if (b.GetPixel(x, y).A == 0) row[x / 8] |= (byte)(0x80 >> (x % 8));
                w.Write(row);
            }
            return ms.ToArray();
        }
    }
}
"@

function RoundRect($g, $brush, [double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [Math]::Max(0.5, 2 * $r)
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $g.FillPath($brush, $path)
}

function Draw([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"
    $g.PixelOffsetMode = "HighQuality"
    $g.Clear([System.Drawing.Color]::Transparent)
    $body = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0x2B, 0x2D, 0x31))
    $key = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0xD0, 0xD4, 0xDA))
    $accent = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0xF5, 0xD5, 0x47))
    # keyboard body, with a lighter rim so it also stands out on a dark taskbar
    $rim = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0x7A, 0x80, 0x8A))
    $bx = $s * 0.03; $by = $s * 0.20; $bw = $s * 0.94; $bh = $s * 0.62
    $t = [Math]::Max(1.0, $s * 0.035)
    RoundRect $g $rim $bx $by $bw $bh ($s * 0.10)
    RoundRect $g $body ($bx + $t) ($by + $t) ($bw - 2 * $t) ($bh - 2 * $t) ($s * 0.10 - $t / 2)
    # three rows of keys; the first key of the middle row (Caps Lock = the Mouse layer key) is yellow
    $pad = $s * 0.09; $gap = $s * 0.045
    $cols = if ($s -le 20) { 4 } else { 6 }
    $kw = ($bw - 2 * $pad - ($cols - 1) * $gap) / $cols
    $kh = ($bh - 2 * $pad - 2 * $gap) / 3
    for ($row = 0; $row -lt 2; $row++) {
        for ($c = 0; $c -lt $cols; $c++) {
            $brush = if ($row -eq 1 -and $c -eq 0) { $accent } else { $key }
            RoundRect $g $brush ($bx + $pad + $c * ($kw + $gap)) ($by + $pad + $row * ($kh + $gap)) $kw $kh ($s * 0.02)
        }
    }
    # space bar
    $sx = $bx + $pad + ($kw + $gap); $sw = ($cols - 2) * $kw + ($cols - 3) * $gap
    RoundRect $g $key $sx ($by + $pad + 2 * ($kh + $gap)) $sw $kh ($s * 0.02)
    $g.Dispose()
    return $bmp
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 256
$images = [System.Drawing.Bitmap[]]($sizes | ForEach-Object { Draw $_ })
[IcoWriter]::Write([System.IO.Path]::GetFullPath($Out), $images)
"wrote $([System.IO.Path]::GetFullPath($Out))"

if ($Preview) {
    # all sizes side by side on light and dark backgrounds, for checking
    [int]$w = ($sizes | Measure-Object -Sum).Sum + 10 * $sizes.Count
    $p = New-Object System.Drawing.Bitmap $w, 540
    $g = [System.Drawing.Graphics]::FromImage($p)
    $g.FillRectangle([System.Drawing.Brushes]::White, 0, 0, $w, 270)
    $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 32, 32, 32))), 0, 270, $w, 270)
    $x = 5
    foreach ($img in $images) { $g.DrawImage($img, $x, 5); $g.DrawImage($img, $x, 275); $x += $img.Width + 10 }
    $p.Save($Preview, [System.Drawing.Imaging.ImageFormat]::Png)
    "preview $Preview"
}
