# Extra safety and behavior tests: odd names, failures mid-run, changed files, big folders, bad data.
# Lines starting with INFO are measurements or limits, not pass/fail.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PhotoSorter.Core.ps1')
. (Join-Path $PSScriptRoot 'Test.Helpers.ps1')
$script:pass = 0; $script:fail = 0
function Check([string]$Name, [bool]$Cond) { if ($Cond) { $script:pass++; Write-Host "PASS  $Name" } else { $script:fail++; Write-Host "FAIL  $Name" } }
function Info([string]$Msg) { Write-Host "INFO  $Msg" }
$isWin = ([IO.Path]::DirectorySeparatorChar -eq '\')
Info ("PowerShell " + $PSVersionTable.PSVersion + " on " + [Environment]::OSVersion.VersionString)

function New-Root { $r = Join-Path ([IO.Path]::GetTempPath()) ("psx-" + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory -Path $r | Out-Null; return $r }
function Snapshot([string]$Dir) { return ((Get-ChildItem -LiteralPath $Dir -Recurse -Force -File | Sort-Object FullName | ForEach-Object { $_.FullName + '|' + (Get-Sha256 $_.FullName) + '|' + $_.LastWriteTimeUtc.Ticks + '|' + [int]$_.Attributes }) -join "`n") }

# ---------- 1. Odd file names ----------
$root = New-Root; $src = Join-Path $root 'in'; $dst = Join-Path $root 'out'; New-Item -ItemType Directory -Path $src, $dst | Out-Null
$arabic = (-join ([char[]](0x0635, 0x0648, 0x0631, 0x0629))) + '.jpg'          # "photo" in Arabic letters
$accent = 'caf' + [char]0xE9 + ' ' + [char]0x00FC + 'ber.jpg'
$names = @($arabic, $accent, 'with [brackets] (1).jpg', "it's #1 & more.jpg", 'two  spaces.jpg', 'UPPER.JPG')
$i = 0
foreach ($n in $names) { $i++; New-ExifJpeg (Join-Path $src $n) ("2021:0{0}:10 10:00:00" -f $i) "n$i" }
$subA = Join-Path $src 'a'; $subB = Join-Path $src 'b'; New-Item -ItemType Directory -Path $subA, $subB | Out-Null
New-ExifJpeg (Join-Path $subA 'same.jpg') '2020:05:05 05:05:05' 'caseA'
New-ExifJpeg (Join-Path $subB 'SAME.JPG') '2020:05:05 06:06:06' 'caseB'     # same name apart from case, different photo
$before = Snapshot $src
$plan = New-SortPlan -Source $src -Dest $dst
$res = Invoke-SortPlan $plan
Check 'names: all 8 files copied, none failed' ($res.Copied -eq 8 -and $res.Failed.Count -eq 0)
Check 'names: Arabic name kept' (Test-Path -LiteralPath (Join-Path $dst "2021/01/$arabic"))
Check 'names: accented name kept' (Test-Path -LiteralPath (Join-Path $dst "2021/02/$accent"))
Check 'names: brackets kept' (Test-Path -LiteralPath (Join-Path $dst '2021/03/with [brackets] (1).jpg'))
Check 'names: names differing only by case did not overwrite each other' (@(Get-ChildItem -LiteralPath (Join-Path $dst '2020/05') -File).Count -eq 2)
Check 'names: source tree identical (content, times, attributes)' ((Snapshot $src) -eq $before)
$u = Undo-SortRun -LogPath $res.LogPath
Check 'names: undo removes all 8' ($u.Removed -eq 8)
$u2 = Undo-SortRun -LogPath $res.LogPath
Check 'names: undoing twice is harmless' ($u2.Removed -eq 0 -and $u2.LeftAlone.Count -eq 0)
Remove-Item -LiteralPath $root -Recurse -Force

# ---------- 2. Things going wrong during the copy ----------
$root = New-Root; $src = Join-Path $root 'in'; $dst = Join-Path $root 'out'; New-Item -ItemType Directory -Path $src, $dst | Out-Null
New-ExifJpeg (Join-Path $src 'ok1.jpg') '2022:01:01 01:01:01' 'ok1'
New-ExifJpeg (Join-Path $src 'ok2.jpg') '2022:02:02 02:02:02' 'ok2'
New-ExifJpeg (Join-Path $src 'vanishes.jpg') '2022:03:03 03:03:03' 'v'
New-ExifJpeg (Join-Path $src 'changes.jpg') '2022:04:04 04:04:04' 'c'
New-ExifJpeg (Join-Path $src 'raced.jpg') '2022:05:05 05:05:05' 'r'
New-ExifJpeg (Join-Path $src 'blocked.jpg') '2022:06:06 06:06:06' 'b'
[IO.File]::WriteAllText((Join-Path $dst '2022-06-marker.txt'), 'x')
$plan = New-SortPlan -Source $src -Dest $dst
# A FILE named like the year folder blocks creating 2022\06 for one photo.
New-Item -ItemType Directory -Path (Join-Path $dst '2022') | Out-Null
[IO.File]::WriteAllText((Join-Path (Join-Path $dst '2022') '06'), 'a file where a folder is needed')
Remove-Item -LiteralPath (Join-Path $src 'vanishes.jpg')                                        # disappears after the preview
[IO.File]::WriteAllBytes((Join-Path $src 'changes.jpg'), [byte[]](1..200))                        # edited after the preview
$racedTarget = ($plan.Items | Where-Object { $_.Source -like '*raced.jpg' }).Target
New-Item -ItemType Directory -Path (Split-Path -Parent $racedTarget) -Force | Out-Null
[IO.File]::WriteAllText($racedTarget, 'someone else created this after the preview')          # appears after the preview
$res = Invoke-SortPlan $plan
Check 'failure: run finishes and reports the problems' ($res.Copied -eq 2 -and $res.Failed.Count -eq 4)
Check 'failure: untouched photos still copied' ((Test-Path (Join-Path $dst '2022/01/ok1.jpg')) -and (Test-Path (Join-Path $dst '2022/02/ok2.jpg')))
Check 'failure: file edited after preview was not left behind' (-not (Test-Path (Join-Path $dst '2022/04/changes.jpg')))
Check 'failure: file that appeared after preview was not overwritten' ([IO.File]::ReadAllText($racedTarget) -eq 'someone else created this after the preview')
Check 'failure: blocking file untouched' ([IO.File]::ReadAllText((Join-Path (Join-Path $dst '2022') '06')) -eq 'a file where a folder is needed')
Check 'failure: log still written' (Test-Path -LiteralPath $res.LogPath)
$u = Undo-SortRun -LogPath $res.LogPath
Check 'failure: undo removes only the 2 good copies' ($u.Removed -eq 2)
Check 'failure: everything that was there before is still there' ((Test-Path $racedTarget) -and (Test-Path (Join-Path $dst '2022-06-marker.txt')) -and (Test-Path -LiteralPath (Join-Path (Join-Path $dst '2022') '06')))
Remove-Item -LiteralPath $root -Recurse -Force

# ---------- 3. File properties ----------
$root = New-Root; $src = Join-Path $root 'in'; $dst = Join-Path $root 'out'; New-Item -ItemType Directory -Path $src, $dst | Out-Null
New-ExifJpeg (Join-Path $src 'ro.jpg') '2018:08:08 08:08:08' 'ro'
(Get-Item (Join-Path $src 'ro.jpg')).LastWriteTime = [datetime]'2018-08-09 10:11:12'
[IO.File]::SetAttributes((Join-Path $src 'ro.jpg'), [IO.FileAttributes]::ReadOnly)
$plan = New-SortPlan -Source $src -Dest $dst; $res = Invoke-SortPlan $plan
$copy = Join-Path $dst '2018/08/ro.jpg'
Check 'props: read-only photo copied' (Test-Path $copy)
Check 'props: modified time of the copy matches the original' ((Get-Item $copy).LastWriteTime -eq [datetime]'2018-08-09 10:11:12')
$u = Undo-SortRun -LogPath $res.LogPath
Check 'props: undo can remove a read-only copy' ($u.Removed -eq 1 -and -not (Test-Path $copy))
Check 'props: original read-only photo still there' (Test-Path (Join-Path $src 'ro.jpg'))
[IO.File]::SetAttributes((Join-Path $src 'ro.jpg'), [IO.FileAttributes]::Normal)
Remove-Item -LiteralPath $root -Recurse -Force

# ---------- 4. Bad or odd data must never crash the date reader ----------
$root = New-Root; $d = $root
New-JpegFromTiff (Join-Path $d 'be.jpg') (New-ExifTiffEx '2017:07:07 07:07:07' $true) 'be'
Check 'dates: big-endian EXIF read' (([PhotoSorterExif]::ReadJpegDateTaken((Join-Path $d 'be.jpg'))) -eq '2017:07:07 07:07:07')
New-JpegFromTiff (Join-Path $d 'zero.jpg') (New-ExifTiffEx '0000:00:00 00:00:00' $false) 'z'
Check 'dates: all-zero date rejected' ($null -eq [PhotoSorterExif]::ReadJpegDateTaken((Join-Path $d 'zero.jpg')))
New-JpegFromTiff (Join-Path $d 'future.jpg') (New-ExifTiffEx '2999:01:01 00:00:00' $false) 'f'
Check 'dates: year 2999 rejected' ($null -eq [PhotoSorterExif]::ReadJpegDateTaken((Join-Path $d 'future.jpg')))
$good = [IO.File]::ReadAllBytes((Join-Path $d 'be.jpg'))
$bad = 0
foreach ($cut in 3, 10, 20, 40, 60, [int]($good.Length / 2)) {
    $t = Join-Path $d "cut$cut.jpg"; [IO.File]::WriteAllBytes($t, $good[0..($cut - 1)])
    try { [void][PhotoSorterExif]::ReadJpegDateTaken($t) } catch { $bad++ }
}
Check 'dates: truncated JPEGs never throw' ($bad -eq 0)
$rnd = New-Object System.Random 12345; $thrown = 0; $wrongHit = 0
for ($k = 0; $k -lt 300; $k++) {
    $b = New-Object byte[] ($rnd.Next(0, 400)); $rnd.NextBytes($b)
    if ($k % 3 -eq 0 -and $b.Length -gt 4) { $b[0] = 0xFF; $b[1] = 0xD8; $b[2] = 0xFF; $b[3] = 0xE1 }
    $t = Join-Path $d 'fuzz.bin'; [IO.File]::WriteAllBytes($t, $b)
    try { $r = [PhotoSorterExif]::ReadJpegDateTaken($t); $h = [PhotoSorterExif]::ReadHeicDateTaken($t); $m = [PhotoSorterExif]::ReadMp4Created($t) } catch { $thrown++ }
}
Check 'dates: 300 random/garbage files never throw (JPEG, HEIC and MP4 readers)' ($thrown -eq 0)
if ($isWin) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $pi = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([System.Drawing.Imaging.PropertyItem])
    $pi.Id = 0x9003; $pi.Type = 2; $val = [System.Text.Encoding]::ASCII.GetBytes('2016:06:15 14:30:00' + [char]0); $pi.Value = $val; $pi.Len = $val.Length
    $bmp.SetPropertyItem($pi); $out = Join-Path $d 'windows-made.jpg'; $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Jpeg); $bmp.Dispose()
    Check 'dates: EXIF written by Windows own JPEG encoder is read correctly' (([PhotoSorterExif]::ReadJpegDateTaken($out)) -eq '2016:06:15 14:30:00')
} else { Info 'Windows JPEG encoder test skipped (not Windows)' }
Remove-Item -LiteralPath $root -Recurse -Force

# ---------- 5. Folder choice rules ----------
$root = New-Root; $s = Join-Path $root 's'; New-Item -ItemType Directory -Path $s | Out-Null
if ($isWin) {
    Check 'rules: Windows folder refused as destination' ($null -ne (Test-FolderChoice $s 'C:\Windows\Photos'))
    Check 'rules: Program Files refused as destination' ($null -ne (Test-FolderChoice $s (Join-Path $env:ProgramFiles 'x')))
    Check 'rules: drive root refused as destination' ($null -ne (Test-FolderChoice $s 'C:\'))
    Check 'rules: Windows folder refused as source' ($null -ne (Test-FolderChoice 'C:\Windows' (Join-Path $root 'd')))
    Check 'rules: missing source refused' ($null -ne (Test-FolderChoice (Join-Path $root 'nope') (Join-Path $root 'd')))
    Check 'rules: destination named like the source with a longer name is allowed' ($null -eq (Test-FolderChoice $s ($s + '-sorted')))
    $junc = Join-Path $root 'junc'; cmd /c mklink /J "$junc" "$s" | Out-Null
    Info ('destination reached through a junction that points at the source: ' + $(if (Test-FolderChoice $s (Join-Path $junc 'x')) { 'refused' } else { 'ALLOWED (known gap)' }))
} else {
    Check 'rules: destination named like the source with a longer name is allowed' ($null -eq (Test-FolderChoice $s ($s + '-sorted')))
}
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue

# ---------- 6. Windows only: locked files, long paths, cloud flags ----------
if ($isWin) {
    $root = New-Root; $src = Join-Path $root 'in'; $dst = Join-Path $root 'out'; New-Item -ItemType Directory -Path $src, $dst | Out-Null
    New-ExifJpeg (Join-Path $src 'free.jpg') '2015:05:05 05:05:05' 'free'
    New-ExifJpeg (Join-Path $src 'locked.jpg') '2015:06:06 06:06:06' 'locked'
    $lock = [IO.File]::Open((Join-Path $src 'locked.jpg'), 'Open', 'ReadWrite', 'None')
    try {
        $plan = New-SortPlan -Source $src -Dest $dst
        $lockedItem = @($plan.Items | Where-Object { $_.Source -like '*locked.jpg' })[0]
        Check 'windows: file open in another program is skipped, not a crash' ($lockedItem.Action -eq 'Skip' -and $lockedItem.Reason -like 'Cannot read*')
        $res = Invoke-SortPlan $plan
        Check 'windows: the other photo is still copied' ($res.Copied -eq 1)
    } finally { $lock.Dispose() }
    Remove-Item -LiteralPath $root -Recurse -Force

    $root = New-Root; $src = Join-Path $root 'in'; New-Item -ItemType Directory -Path $src | Out-Null
    New-ExifJpeg (Join-Path $src 'long.jpg') '2014:04:04 04:04:04' 'long'
    $longDst = Join-Path $root ('d' * 120); $longDst = Join-Path $longDst ('e' * 100); New-Item -ItemType Directory -Path $longDst -Force | Out-Null
    $plan = New-SortPlan -Source $src -Dest $longDst
    $it = @($plan.Items)[0]
    Check 'windows: destination path that would pass the old 260 limit is skipped with a reason' ($it.Action -eq 'Skip' -and $it.Reason -like '*too long*')
    Remove-Item -LiteralPath $root -Recurse -Force

    $root = New-Root; $src = Join-Path $root 'in'; New-Item -ItemType Directory -Path $src | Out-Null
    $f = Join-Path $src 'x.jpg'; New-ExifJpeg $f '2013:03:03 03:03:03' 'x'
    $stuck = @()
    foreach ($flag in 0x1000, 0x40000, 0x400000) {
        try { [IO.File]::SetAttributes($f, [IO.FileAttributes]([int][IO.FileAttributes]::Normal -bor $flag)) } catch { }
        if (([int](Get-Item $f -Force).Attributes -band $flag) -ne 0) { $stuck += ('0x{0:X}' -f $flag) }
        [IO.File]::SetAttributes($f, [IO.FileAttributes]::Normal)
    }
    Info ("cloud-file attribute bits that Windows let me set on a normal file: " + $(if ($stuck.Count) { $stuck -join ', ' } else { 'none' }) + ". Real OneDrive placeholders are NOT simulated here.")
    Remove-Item -LiteralPath $root -Recurse -Force
}

# ---------- 7. A bigger folder ----------
$root = New-Root; $src = Join-Path $root 'in'; $dst = Join-Path $root 'out'; New-Item -ItemType Directory -Path $src, $dst | Out-Null
$tpl = Join-Path $root 'tpl.jpg'; New-ExifJpeg $tpl '2019:01:15 12:00:00' 'tpl'
$tb = [IO.File]::ReadAllBytes($tpl)
$pos = -1; $needle = [Text.Encoding]::ASCII.GetBytes('2019:01:15')
for ($p = 0; $p -lt $tb.Length - 10; $p++) { $m = $true; for ($q = 0; $q -lt 10; $q++) { if ($tb[$p + $q] -ne $needle[$q]) { $m = $false; break } }; if ($m) { $pos = $p; break } }
$N = 1200
$sw = [Diagnostics.Stopwatch]::StartNew()
for ($k = 0; $k -lt $N; $k++) {
    $b = [byte[]]($tb.Clone()); $day = ($k % 28) + 1; $mon = ($k % 12) + 1; $yr = 2000 + ($k % 24)
    $txt = '{0:D4}:{1:D2}:{2:D2}' -f $yr, $mon, $day; $bytes = [Text.Encoding]::ASCII.GetBytes($txt); [Array]::Copy($bytes, 0, $b, $pos, 10)
    $b2 = New-Object byte[] ($b.Length + 8); [Array]::Copy($b, $b2, $b.Length); [Array]::Copy([BitConverter]::GetBytes([int64]$k), 0, $b2, $b.Length, 8)
    $sub = Join-Path $src ('batch' + ($k % 5)); if (-not (Test-Path $sub)) { New-Item -ItemType Directory -Path $sub | Out-Null }
    [IO.File]::WriteAllBytes((Join-Path $sub ("IMG_{0:D5}.jpg" -f $k)), $b2)
}
Info ("built $N test photos in " + [int]$sw.Elapsed.TotalSeconds + "s")
$snap = Snapshot $src
$sw.Restart(); $plan = New-SortPlan -Source $src -Dest $dst; $tPlan = [int]$sw.Elapsed.TotalSeconds
$sw.Restart(); $res = Invoke-SortPlan $plan; $tRun = [int]$sw.Elapsed.TotalSeconds
Info "big folder: preview ${tPlan}s, copy ${tRun}s for $N photos"
Check 'big: all copied, none failed' ($res.Copied -eq $N -and $res.Failed.Count -eq 0)
Check 'big: source unchanged' ((Snapshot $src) -eq $snap)
$srcHashes = (Get-ChildItem -LiteralPath $src -Recurse -File | ForEach-Object { Get-Sha256 $_.FullName } | Sort-Object) -join ','
$dstHashes = (Get-ChildItem -LiteralPath $dst -Recurse -File -Filter *.jpg | ForEach-Object { Get-Sha256 $_.FullName } | Sort-Object) -join ','
Check 'big: every copy is byte-identical to an original' ($srcHashes -eq $dstHashes)
$plan2 = New-SortPlan -Source $src -Dest $dst
Check 'big: second run has nothing to copy' ((Get-PlanSummary $plan2).ToCopy -eq 0)
$u = Undo-SortRun -LogPath $res.LogPath
Check 'big: undo removes all copies' ($u.Removed -eq $N -and @(Get-ChildItem -LiteralPath $dst -Recurse -File -Filter *.jpg).Count -eq 0)
Remove-Item -LiteralPath $root -Recurse -Force

Write-Host "`n$script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { exit 1 }
