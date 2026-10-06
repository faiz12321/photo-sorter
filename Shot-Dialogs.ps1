# Shows the real refusal message box in a separate process, photographs the screen, then closes it.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
. (Join-Path $PSScriptRoot 'PhotoSorter.Core.ps1')
$tmp = Join-Path $env:RUNNER_TEMP 'dlg'; New-Item -ItemType Directory -Path (Join-Path $tmp 'OneDrive\Pics'), (Join-Path $tmp 'plain') -Force | Out-Null
$msg = Test-FolderChoice (Join-Path $tmp 'OneDrive\Pics') (Join-Path $tmp 'plain\out')
Write-Host "Refusal text: $msg"
$txt = Join-Path $tmp 'msg.txt'; [IO.File]::WriteAllText($txt, $msg)
$child = Join-Path $tmp 'show.ps1'
Set-Content -LiteralPath $child -Value @"
Add-Type -AssemblyName System.Windows.Forms
[void][System.Windows.Forms.MessageBox]::Show([IO.File]::ReadAllText('$txt'), 'Photo Sorter')
"@
$p = Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',$child -PassThru
Start-Sleep -Seconds 6
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size); $g.Dispose()
$path = Join-Path $tmp 'refusal-box.png'; $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Host "B64BEGIN refusal-box.png"
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
for ($i = 0; $i -lt $b64.Length; $i += 200) { Write-Host $b64.Substring($i, [Math]::Min(200, $b64.Length - $i)) }
Write-Host "B64END refusal-box.png"
try { Stop-Process -Id $p.Id -Force } catch { }
Write-Host 'done'
