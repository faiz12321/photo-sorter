# Private, isolated regression fixtures. Run beside PhotoSorter.Core.ps1 on Windows.
# Tests required safe behavior. Only disposable temp data is used.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PhotoSorter.Core.ps1')
if ([IO.Path]::DirectorySeparatorChar -ne '\') { throw 'These junction fixtures require Windows.' }
$script:passes = 0; $script:failures = 0
function Check([string]$Name, [bool]$Safe) {
    if ($Safe) { $script:passes++; Write-Host "PASS $Name" }
    else { $script:failures++; Write-Host "FAIL $Name" }
}
function New-Fixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('ps-safety-' + [guid]::NewGuid().ToString('N'))
    $src = Join-Path $root 'source'; $dst = Join-Path $root 'sorted'; $outside = Join-Path $root 'outside'
    New-Item -ItemType Directory -Path $src,$dst,$outside | Out-Null
    # The extension is enough for the file-date fallback; no real photo is used.
    $photo = Join-Path $src 'sample.jpg'
    [IO.File]::WriteAllText($photo, 'DISPOSABLE FIXTURE ' + [guid]::NewGuid().ToString('N'))
    (Get-Item -LiteralPath $photo).LastWriteTime = [datetime]'2024-06-15T12:00:00'
    return [pscustomobject]@{Root=$root; Source=$src; Dest=$dst; Outside=$outside; Photo=$photo; Junction=$null}
}
function Add-Junction($Fixture, [string]$Path, [string]$Target) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
    $Fixture.Junction = $Path
}
function Remove-Fixture($Fixture) {
    # Unlink first so recursive cleanup cannot follow our fixture junction.
    if ($Fixture.Junction -and (Test-Path -LiteralPath $Fixture.Junction)) {
        [IO.Directory]::Delete($Fixture.Junction)
    }
    Remove-Item -LiteralPath $Fixture.Root -Recurse -Force
}

# 1. A normal destination root with a linked month below it.
$f = New-Fixture
try {
    Add-Junction $f (Join-Path $f.Dest '2024\06') $f.Outside
    $refused = $false
    try { $plan = New-SortPlan $f.Source $f.Dest; $result = Invoke-SortPlan $plan }
    catch { $refused = $true }
    Check 'existing month junction does not receive a copy outside the destination' (-not (Test-Path -LiteralPath (Join-Path $f.Outside 'sample.jpg')))
    Check 'existing month junction is refused or the item is explicitly failed/skipped' ($refused -or ($result.Copied -eq 0))
} finally { Remove-Fixture $f }

# 2. Destination changes between Preview and Copy.
$f = New-Fixture
try {
    $plan = New-SortPlan $f.Source $f.Dest
    Add-Junction $f (Join-Path $f.Dest '2024\06') $f.Outside
    $refused = $false
    try { $result = Invoke-SortPlan $plan } catch { $refused = $true }
    Check 'junction introduced after preview does not redirect the copy' (-not (Test-Path -LiteralPath (Join-Path $f.Outside 'sample.jpg')))
    Check 'copy revalidates its actual target after preview' ($refused -or ($result.Copied -eq 0))
} finally { Remove-Fixture $f }

# 3. A selected JSON log is not proof that the tool created a file.
$f = New-Fixture
try {
    $logDir = Join-Path $f.Dest 'PhotoSorter-logs'; New-Item -ItemType Directory -Path $logDir | Out-Null
    $logPath = Join-Path $logDir 'undo-forged.json'
    $fake = [pscustomobject]@{
        Tool='PhotoSorter'; Created=(Get-Date).ToString('s'); Source=$f.Source; Dest=$f.Dest
        Files=@([pscustomobject]@{Path=$f.Photo; Hash=(Get-Sha256 $f.Photo); From=$f.Photo})
        Dirs=@(); Failed=@()
    }
    $fake | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $logPath -Encoding UTF8
    $refused = $false
    try { $undo = Undo-SortRun $logPath } catch { $refused = $true }
    Check 'forged undo log cannot delete an original with a matching hash' (Test-Path -LiteralPath $f.Photo)
    Check 'forged undo log is rejected before deletion' $refused
} finally { Remove-Fixture $f }

# 4. Even a path inside the destination can point to a pre-existing file.
$f = New-Fixture
try {
    $existing = Join-Path $f.Dest 'someone-elses.jpg'; [IO.File]::WriteAllText($existing, 'EXISTING DISPOSABLE FILE')
    $logDir = Join-Path $f.Dest 'PhotoSorter-logs'; New-Item -ItemType Directory -Path $logDir | Out-Null
    $logPath = Join-Path $logDir 'undo-forged-inside.json'
    [pscustomobject]@{
        Tool='PhotoSorter'; Created=(Get-Date).ToString('s'); Source=$f.Source; Dest=$f.Dest
        Files=@([pscustomobject]@{Path=$existing; Hash=(Get-Sha256 $existing); From=$f.Photo})
        Dirs=@(); Failed=@()
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $logPath -Encoding UTF8
    try { $undo = Undo-SortRun $logPath } catch { }
    Check 'forged log cannot delete a pre-existing destination file' (Test-Path -LiteralPath $existing)
} finally { Remove-Fixture $f }

# 5. A genuine receipt with a changed protected payload must fail closed.
$f = New-Fixture
try {
    $result = Invoke-SortPlan (New-SortPlan $f.Source $f.Dest)
    $outer = Get-Content -LiteralPath $result.LogPath -Raw | ConvertFrom-Json
    $bytes = [Convert]::FromBase64String($outer.ProtectedReceipt); $bytes[20] = $bytes[20] -bxor 1
    $outer.ProtectedReceipt = [Convert]::ToBase64String($bytes)
    $outer | ConvertTo-Json | Set-Content -LiteralPath $result.LogPath -Encoding UTF8
    $refused = $false; try { $u = Undo-SortRun $result.LogPath } catch { $refused = $true }
    Check 'edited protected receipt rejected' $refused
    Check 'edited receipt leaves copies and original intact' ((Test-Path -LiteralPath $f.Photo) -and (Test-Path -LiteralPath $result.CreatedFiles[0].Path))
} finally { Remove-Fixture $f }

# 6. Month folder becomes a junction before Undo.
$f = New-Fixture
try {
    $result = Invoke-SortPlan (New-SortPlan $f.Source $f.Dest)
    $month = Join-Path $f.Dest '2024\06'; $moved = Join-Path $f.Outside 'saved'
    Move-Item -LiteralPath $month -Destination $moved
    Add-Junction $f $month $moved
    $refused = $false; try { $u = Undo-SortRun $result.LogPath } catch { $refused = $true }
    Check 'junction introduced before Undo is rejected' $refused
    Check 'Undo never deletes through the junction' (Test-Path -LiteralPath (Join-Path $moved 'sample.jpg'))
} finally { Remove-Fixture $f }

# 7. Changed source and UI row mapping.
$f = New-Fixture
try {
    $plan = New-SortPlan $f.Source $f.Dest
    [IO.File]::AppendAllText($f.Photo, 'changed after preview')
    $result = Invoke-SortPlan $plan
    $row = Get-CopyRowOutcome $f.Photo $result
    Check 'changed source is not copied' ($result.Copied -eq 0 -and $result.Failed.Count -eq 1)
    Check 'failed UI row is not labelled Copied' ($row.Label -eq 'Failed' -and $row.Note -like '*changed after Preview*')
    $plan = New-SortPlan $f.Source $f.Dest; $result2 = Invoke-SortPlan $plan
    Check 'success UI row labelled Copied' ((Get-CopyRowOutcome $f.Photo $result2).Label -eq 'Copied')
    Check 'receipts have unique names and both survive' ($result.LogPath -ne $result2.LogPath -and (Test-Path $result.LogPath) -and (Test-Path $result2.LogPath))
} finally { Remove-Fixture $f }

# 8. Calendar-invalid EXIF falls back rather than aborting Preview.
. (Join-Path $PSScriptRoot 'Test.Helpers.ps1')
$f = New-Fixture
try {
    foreach ($date in @('2024:02:31 12:00:00','2024:06:15 25:00:00','2024:06:15 12:99:00')) {
        New-ExifJpeg $f.Photo $date 'invalid-date'
        (Get-Item -LiteralPath $f.Photo).LastWriteTime = [datetime]'2020-07-04T12:00:00'
        $plan = New-SortPlan $f.Source $f.Dest
        Check ('invalid EXIF ' + $date + ' uses file date') ($plan.Items[0].DateFrom -eq 'File date' -and $plan.Items[0].Target -like '*2020*07*')
    }
} finally { Remove-Fixture $f }
Write-Host "$script:passes passed, $script:failures failed"
if ($script:failures) { exit 1 }
