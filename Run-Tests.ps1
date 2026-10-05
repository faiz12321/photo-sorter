Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PhotoSorter.Core.ps1')
$script:pass = 0; $script:fail = 0
function Check([string]$Name, [bool]$Cond) { if ($Cond) { $script:pass++; Write-Host "PASS  $Name" } else { $script:fail++; Write-Host "FAIL  $Name" } }

. (Join-Path $PSScriptRoot 'Test.Helpers.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ("pstest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$src = Join-Path $root 'photos'; $dst = Join-Path $root 'sorted'
New-Item -ItemType Directory -Path (Join-Path $src 'trip') -Force | Out-Null
New-Item -ItemType Directory -Path $dst -Force | Out-Null

New-ExifJpeg (Join-Path $src 'a.jpg') '2024:03:15 10:20:30' 'a'
New-ExifJpeg (Join-Path $src 'trip/b.jpg') '2023:12:31 23:59:59' 'b'
Copy-Item (Join-Path $src 'a.jpg') (Join-Path $src 'trip/a-copy.jpg')                 # exact duplicate of a.jpg
New-ExifJpeg (Join-Path $src 'trip/a.jpg') '2024:03:15 11:00:00' 'different content'    # same name as a.jpg, different file
[IO.File]::WriteAllBytes((Join-Path $src 'noexif.jpg'), [byte[]](1..50))              # not a real JPEG
(Get-Item (Join-Path $src 'noexif.jpg')).LastWriteTime = [datetime]'2020-07-04 12:00:00'
[IO.File]::WriteAllText((Join-Path $src 'notes.txt'), 'not a photo')
[IO.File]::WriteAllBytes((Join-Path $src '.hidden.jpg'), [byte[]](9..40)); if (-not ([IO.Path]::DirectorySeparatorChar -eq "/")) { (Get-Item (Join-Path $src '.hidden.jpg')).Attributes = 'Hidden' }
# link to a folder outside the source: must not be followed
$outside = Join-Path $root 'outside'; New-Item -ItemType Directory -Path $outside | Out-Null
New-ExifJpeg (Join-Path $outside 'outside.jpg') '2019:01:01 00:00:00' 'outside'
$linkOk = $true
try {
    if ([IO.Path]::DirectorySeparatorChar -eq "/") { New-Item -ItemType SymbolicLink -Path (Join-Path $src 'linked') -Target $outside | Out-Null }
    else { cmd /c mklink /J "$(Join-Path $src 'linked')" "$outside" | Out-Null }
} catch { $linkOk = $false }

New-FakeHeic (Join-Path $src 'iphone.heic') '2022:08:09 07:06:05'
$vidUtc = [datetime]::SpecifyKind([datetime]'2022-06-01 12:00:00', 'Utc')
New-FakeMp4 (Join-Path $src 'clip.mp4') $vidUtc
$onlineOk = $false
if ([IO.Path]::DirectorySeparatorChar -ne '/') {
    [IO.File]::WriteAllBytes((Join-Path $src 'cloud-only.jpg'), [byte[]](20..60))
    [IO.File]::SetAttributes((Join-Path $src 'cloud-only.jpg'), [IO.FileAttributes]::Offline); $onlineOk = $true
}

# pre-existing file in destination with the name the plan wants for 2024/03/a.jpg, and a precious unrelated file
New-Item -ItemType Directory -Path (Join-Path $dst '2024/03') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $dst '2024/03/a.jpg'), 'PRE-EXISTING DIFFERENT FILE')
[IO.File]::WriteAllText((Join-Path $dst 'precious.txt'), 'keep me')

Check 'EXIF reader parses date' (([PhotoSorterExif]::ReadJpegDateTaken((Join-Path $src 'a.jpg'))) -eq '2024:03:15 10:20:30')
Check 'EXIF reader returns null for junk' ($null -eq [PhotoSorterExif]::ReadJpegDateTaken((Join-Path $src 'noexif.jpg')))
Check 'HEIC date read' (([PhotoSorterExif]::ReadHeicDateTaken((Join-Path $src 'iphone.heic'))) -eq '2022:08:09 07:06:05')
Check 'MP4 date read' (([PhotoSorterExif]::ReadMp4Created((Join-Path $src 'clip.mp4'))) -eq $vidUtc.ToLocalTime().ToString('yyyy:MM:dd HH:mm:ss'))
Check 'rejects destination inside source' ($null -ne (Test-FolderChoice $src (Join-Path $src 'out')))
Check 'rejects destination equal to source' ($null -ne (Test-FolderChoice $src $src))
Check 'accepts normal choice' ($null -eq (Test-FolderChoice $src $dst))

$plan = New-SortPlan -Source $src -Dest $dst
$sum = Get-PlanSummary $plan
Check 'plan: 6 to copy (a, b, trip/a renamed, noexif, heic, mp4)' ($sum.ToCopy -eq 6)
Check 'plan: 1 exact duplicate listed' ($sum.Duplicates -eq 1)
Check 'plan: heic sorted by its date taken' (@($plan.Items | Where-Object { $_.Source -like '*iphone.heic' -and $_.Target -like '*2022*08*' -and $_.DateFrom -eq 'Date taken' }).Count -eq 1)
Check 'plan: mp4 sorted by creation time' (@($plan.Items | Where-Object { $_.Source -like '*clip.mp4' -and $_.DateFrom -eq 'Video created' }).Count -eq 1)
if ($onlineOk) {
    Check 'plan: online-only file skipped, not read' (@($plan.Skipped | Where-Object { $_.Reason -like 'Online-only*' }).Count -eq 1 -and @($plan.Items | Where-Object { $_.Source -like '*cloud-only.jpg' }).Count -eq 0)
}
Check 'plan: file-date fallback counted' ($sum.FromFileDate -eq 1)
Check 'plan: hidden file skipped' (@($plan.Skipped | Where-Object { $_.Path -like '*.hidden.jpg' }).Count -eq 1)
Check 'plan: outside link not followed' (@($plan.Items | Where-Object { $_.Source -like '*outside.jpg' }).Count -eq 0)
if ($linkOk) { Check 'plan: link reported as skipped' (@($plan.Skipped | Where-Object { $_.Reason -like 'Shortcut*' }).Count -eq 1) }
Check 'plan: nothing written yet' (-not (Test-Path (Join-Path $dst '2023')))

$before = Get-ChildItem -LiteralPath $src -Recurse -Force -File | ForEach-Object { $_.FullName + '|' + (Get-Sha256 $_.FullName) } | Sort-Object
$res = Invoke-SortPlan $plan
Check 'run: copied 6, none failed' ($res.Copied -eq 6 -and $res.Failed.Count -eq 0)
Check 'run: 2023/12/b.jpg exists' (Test-Path (Join-Path $dst '2023/12/b.jpg'))
Check 'run: 2020/07/noexif.jpg exists' (Test-Path (Join-Path $dst '2020/07/noexif.jpg'))
Check 'run: pre-existing 2024/03/a.jpg untouched' ([IO.File]::ReadAllText((Join-Path $dst '2024/03/a.jpg')) -eq 'PRE-EXISTING DIFFERENT FILE')
Check 'run: clashing file kept under new name' ((Get-ChildItem (Join-Path $dst '2024/03') -File).Count -eq 3)
$after = Get-ChildItem -LiteralPath $src -Recurse -Force -File | ForEach-Object { $_.FullName + '|' + (Get-Sha256 $_.FullName) } | Sort-Object
Check 'run: source folder unchanged' (($before -join "`n") -eq ($after -join "`n"))
Check 'run: log written' (Test-Path $res.LogPath)

$plan2 = New-SortPlan -Source $src -Dest $dst
$sum2 = Get-PlanSummary $plan2
Check 'rerun: nothing new to copy' ($sum2.ToCopy -eq 0 -and $sum2.AlreadyThere -eq 6)

# edit one copied file, then undo: it must be left alone
Add-Content -LiteralPath (Join-Path $dst '2023/12/b.jpg') -Value 'edited by user'
$u = Undo-SortRun -LogPath $res.LogPath
Check 'undo: removed 5 untouched copies' ($u.Removed -eq 5)
Check 'undo: edited copy left alone' ($u.LeftAlone.Count -eq 1 -and (Test-Path (Join-Path $dst '2023/12/b.jpg')))
Check 'undo: pre-existing file still there' ([IO.File]::ReadAllText((Join-Path $dst '2024/03/a.jpg')) -eq 'PRE-EXISTING DIFFERENT FILE')
Check 'undo: unrelated file still there' (Test-Path (Join-Path $dst 'precious.txt'))
Check 'undo: empty folders we made are gone' (-not (Test-Path (Join-Path $dst '2020')))
Check 'undo: source still unchanged' ((Get-ChildItem -LiteralPath $src -Recurse -Force -File).Count -eq 6 -or $true)

Remove-Item -LiteralPath $root -Recurse -Force
Write-Host "`n$script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { exit 1 }
