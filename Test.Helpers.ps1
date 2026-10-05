Set-StrictMode -Version 2.0
function New-ExifTiff([string]$Taken) {
    $tiff = New-Object System.Collections.Generic.List[byte]
    $le = { param($v, $n) for ($i = 0; $i -lt $n; $i++) { $tiff.Add([byte](($v -shr (8 * $i)) -band 0xFF)) } }
    $tiff.AddRange([byte[]][char[]]'II'); & $le 42 2; & $le 8 4
    # IFD0 at 8: 1 entry (ExifIFD pointer -> 26)
    & $le 1 2; & $le 0x8769 2; & $le 4 2; & $le 1 4; & $le 26 4; & $le 0 4
    # ExifIFD at 26: 1 entry DateTimeOriginal, 20 bytes at offset 44
    & $le 1 2; & $le 0x9003 2; & $le 2 2; & $le 20 4; & $le 44 4; & $le 0 4
    $tiff.AddRange([byte[]][char[]]$Taken); $tiff.Add(0)
    return ,$tiff.ToArray()
}
function New-ExifJpeg([string]$Path, [string]$Taken, [string]$Salt = '') {
    $tiff = New-ExifTiff $Taken
    $seg = New-Object System.Collections.Generic.List[byte]
    $seg.AddRange([byte[]][char[]]'Exif'); $seg.Add(0); $seg.Add(0); $seg.AddRange($tiff)
    $len = $seg.Count + 2
    $out = New-Object System.Collections.Generic.List[byte]
    $out.Add(0xFF); $out.Add(0xD8); $out.Add(0xFF); $out.Add(0xE1); $out.Add([byte]($len -shr 8)); $out.Add([byte]($len -band 0xFF))
    $out.AddRange($seg)
    $out.AddRange([byte[]][char[]]("salt:" + $Salt)); $out.Add(0xFF); $out.Add(0xD9)
    [IO.File]::WriteAllBytes($Path, $out.ToArray())
}

function New-FakeHeic([string]$Path, [string]$Taken) {
    $tiff = New-ExifTiff $Taken
    $b = New-Object System.Collections.Generic.List[byte]
    $b.AddRange([byte[]][char[]]'....ftypheic'); for ($i = 0; $i -lt 300; $i++) { $b.Add(7) }
    $b.AddRange([byte[]](0, 0, 0, 6)); $b.AddRange([byte[]][char[]]'Exif'); $b.Add(0); $b.Add(0); $b.AddRange($tiff)
    [IO.File]::WriteAllBytes($Path, $b.ToArray())
}
function New-FakeMp4([string]$Path, [datetime]$UtcCreated) {
    $secs = [uint32](($UtcCreated - [datetime]'1904-01-01').TotalSeconds)
    $be = { param($v) [byte[]]@((($v -shr 24) -band 255), (($v -shr 16) -band 255), (($v -shr 8) -band 255), ($v -band 255)) }
    $mvhd = New-Object System.Collections.Generic.List[byte]
    $mvhd.AddRange(([byte[]](& $be 108))); $mvhd.AddRange([byte[]][char[]]'mvhd'); $mvhd.AddRange([byte[]](0, 0, 0, 0)); $mvhd.AddRange(([byte[]](& $be $secs))); $mvhd.AddRange(([byte[]](& $be $secs)))
    while ($mvhd.Count -lt 108) { $mvhd.Add(0) }
    $moov = New-Object System.Collections.Generic.List[byte]
    $moov.AddRange(([byte[]](& $be (8 + $mvhd.Count)))); $moov.AddRange([byte[]][char[]]'moov'); $moov.AddRange($mvhd)
    $all = New-Object System.Collections.Generic.List[byte]
    $all.AddRange(([byte[]](& $be 16))); $all.AddRange([byte[]][char[]]'ftypisom'); $all.AddRange([byte[]](0, 0, 0, 0))
    $all.AddRange(([byte[]](& $be 40))); $all.AddRange([byte[]][char[]]'mdat'); for ($i = 0; $i -lt 32; $i++) { $all.Add(1) }   # big data first, as in many phone videos
    $all.AddRange($moov)
    [IO.File]::WriteAllBytes($Path, $all.ToArray())
}
