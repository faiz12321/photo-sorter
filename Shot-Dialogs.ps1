# Opens the real folder dialog and the refusal message box, photographs the screen, closes them.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
. (Join-Path $PSScriptRoot 'PhotoSorter.Core.ps1')
$src = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'PhotoSorter.ps1') -Raw
$desc = [regex]::Match($src, "Pick-Folder '(Choose the folder with your photos[^']*)'").Groups[1].Value
Write-Host "Dialog text: $desc"
$tmp = Join-Path $env:RUNNER_TEMP 'dlg'; New-Item -ItemType Directory -Path (Join-Path $tmp 'OneDrive\Pics'), (Join-Path $tmp 'plain') -Force | Out-Null
$msg = Test-FolderChoice (Join-Path $tmp 'OneDrive\Pics') (Join-Path $tmp 'plain\out')
Write-Host "Refusal text: $msg"
function Shot([string]$Name) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size); $g.Dispose()
    $path = Join-Path $tmp $Name; $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Host "B64BEGIN $Name"
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
    for ($i = 0; $i -lt $b64.Length; $i += 200) { Write-Host $b64.Substring($i, [Math]::Min(200, $b64.Length - $i)) }
    Write-Host "B64END $Name"
}
$script:which = ''
$timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 2500
$timer.Add_Tick({ $timer.Stop(); Shot $script:which; [System.Windows.Forms.SendKeys]::SendWait('{ESC}') })
$script:which = 'folder-dialog.png'; $timer.Start()
$d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = $desc; [void]$d.ShowDialog()
$script:which = 'refusal-box.png'; $timer.Start()
[void][System.Windows.Forms.MessageBox]::Show($msg, 'Photo Sorter')
Write-Host 'done'
