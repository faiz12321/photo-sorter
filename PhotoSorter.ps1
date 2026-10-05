# Photo Sorter - simple window. Copies photos into Year\Month folders. Your originals are never changed.
param([switch]$SelfTest, [string]$DemoSource, [string]$DemoDest, [string]$ShotDir)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'PhotoSorter.Core.ps1')

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Photo Sorter'; $form.Size = New-Object System.Drawing.Size(820, 600); $form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 26, 32); $form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

function Add-Label($text, $x, $y, $w = 760) { $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.Size = New-Object System.Drawing.Size($w, 24); $form.Controls.Add($l); return $l }
function Add-Button($text, $x, $y, $w = 150) { $b = New-Object System.Windows.Forms.Button; $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size($w, 34); $b.FlatStyle = 'Flat'; $b.BackColor = [System.Drawing.Color]::FromArgb(52, 120, 246); $b.ForeColor = [System.Drawing.Color]::White; $form.Controls.Add($b); return $b }
function Add-Box($x, $y) { $t = New-Object System.Windows.Forms.TextBox; $t.Location = New-Object System.Drawing.Point($x, $y); $t.Size = New-Object System.Drawing.Size(540, 28); $t.ReadOnly = $true; $form.Controls.Add($t); return $t }

[void](Add-Label '1. Folder with your photos (it is only read, never changed)' 20 15)
$srcBox = Add-Box 20 42; $srcBtn = Add-Button 'Choose...' 575 40
[void](Add-Label '2. Folder where the sorted copies go (a new or empty folder is best)' 20 90)
$dstBox = Add-Box 20 117; $dstBtn = Add-Button 'Choose...' 575 115
$previewBtn = Add-Button '3. Preview' 20 165 160
$copyBtn = Add-Button '4. Copy photos' 190 165 160; $copyBtn.Enabled = $false
$undoBtn = Add-Button 'Undo a run...' 360 165 160

$status = Add-Label 'Choose two folders to start.' 20 210 760
$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object System.Drawing.Point(20, 240); $list.Size = New-Object System.Drawing.Size(765, 300); $list.View = 'Details'; $list.FullRowSelect = $true
$list.BackColor = [System.Drawing.Color]::FromArgb(36, 39, 48); $list.ForeColor = [System.Drawing.Color]::White
[void]$list.Columns.Add('What happens', 130); [void]$list.Columns.Add('Photo', 330); [void]$list.Columns.Add('Goes to / note', 290)
$form.Controls.Add($list)

$script:plan = $null
function Pick-Folder($title) { $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = $title; if ($d.ShowDialog() -eq 'OK') { return $d.SelectedPath } return $null }
$srcBtn.Add_Click({ $p = Pick-Folder 'Choose the folder with your photos'; if ($p) { $srcBox.Text = $p; $copyBtn.Enabled = $false; $script:plan = $null } })
$dstBtn.Add_Click({ $p = Pick-Folder 'Choose where the sorted copies should go'; if ($p) { $dstBox.Text = $p; $copyBtn.Enabled = $false; $script:plan = $null } })

$previewBtn.Add_Click({
    $err = Test-FolderChoice $srcBox.Text $dstBox.Text
    if ($err) { [void][System.Windows.Forms.MessageBox]::Show($err, 'Photo Sorter'); return }
    $form.Cursor = 'WaitCursor'; $status.Text = 'Looking through your photos...'; $form.Refresh()
    try {
        $script:plan = New-SortPlan -Source $srcBox.Text -Dest $dstBox.Text
        $s = Get-PlanSummary $script:plan
        $list.Items.Clear()
        foreach ($i in $script:plan.Items) {
            $label = switch ($i.Action) { 'Copy' { 'Copy' } 'Duplicate' { 'Duplicate - not copied' } 'AlreadyThere' { 'Already there' } default { 'Skipped' } }
            $note = if ($i.Action -eq 'Copy') { $i.Target.Substring($script:plan.Dest.Length).TrimStart('\', '/') + $(if ($i.Reason) { '  (' + $i.Reason + ')' } else { '' }) } else { $i.Reason }
            $row = New-Object System.Windows.Forms.ListViewItem($label); [void]$row.SubItems.Add($i.Source); [void]$row.SubItems.Add($note); [void]$list.Items.Add($row)
        }
        foreach ($k in $script:plan.Skipped) { $row = New-Object System.Windows.Forms.ListViewItem('Skipped'); [void]$row.SubItems.Add($k.Path); [void]$row.SubItems.Add($k.Reason); [void]$list.Items.Add($row) }
        $status.Text = "$($s.ToCopy) to copy ($($s.FromFileDate) sorted by file date because no date taken was found), $($s.Duplicates) exact duplicates left out, $($s.AlreadyThere) already there, $($s.Skipped) skipped. Nothing has been changed yet."
        $copyBtn.Enabled = ($s.ToCopy -gt 0)
    } catch { [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Photo Sorter') }
    finally { $form.Cursor = 'Default' }
})

$copyBtn.Add_Click({
    if (-not $script:plan) { return }
    $s = Get-PlanSummary $script:plan
    $ask = "Copy $($s.ToCopy) photos into:`n$($script:plan.Dest)`n`nYour original photos stay where they are. Nothing is deleted or overwritten."
    if (-not $SelfTest) { if ([System.Windows.Forms.MessageBox]::Show($ask, 'Photo Sorter', 'OKCancel') -ne 'OK') { return } }
    $form.Cursor = 'WaitCursor'; $status.Text = 'Copying...'; $form.Refresh()
    try {
        $r = Invoke-SortPlan $script:plan
        $status.Text = "Done. Copied $($r.Copied), $($r.Failed.Count) failed. Undo log: $($r.LogPath)"
        $copyBtn.Enabled = $false; $script:plan = $null
    } catch { [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Photo Sorter') }
    finally { $form.Cursor = 'Default' }
})

$undoBtn.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = 'Photo Sorter undo log (undo-*.json)|undo-*.json'; $d.Title = 'Choose the undo log of the run to undo'
    if ($d.ShowDialog() -ne 'OK') { return }
    if ([System.Windows.Forms.MessageBox]::Show('Remove only the copies this run made? Anything you changed since, and everything that was already there, is left alone.', 'Photo Sorter', 'OKCancel') -ne 'OK') { return }
    try { $u = Undo-SortRun -LogPath $d.FileName; $status.Text = "Undone. Removed $($u.Removed) copies, left $($u.LeftAlone.Count) changed files alone." }
    catch { [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Photo Sorter') }
})

function Save-Shot([string]$Name) {
    $form.Refresh(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 400
    $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($form.Location, [System.Drawing.Point]::Empty, $form.Size)
    $g.Dispose()
    $path = Join-Path $ShotDir $Name
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Host "SHOT $Name $((Get-Item $path).Length) bytes"
    Write-Host "B64BEGIN $Name"
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
    for ($i = 0; $i -lt $b64.Length; $i += 200) { Write-Host $b64.Substring($i, [Math]::Min(200, $b64.Length - $i)) }
    Write-Host "B64END $Name"
}

if ($SelfTest) {
    if (-not $DemoSource) { Write-Host "GUI built: $($form.Controls.Count) controls"; $form.Dispose(); exit 0 }
    # Drive the real window: choose folders, press Preview, press Copy, and photograph it.
    $srcBox.Text = $DemoSource; $dstBox.Text = $DemoDest
    $form.StartPosition = 'Manual'; $form.Location = New-Object System.Drawing.Point(20, 20)
    $form.TopMost = $true; $form.Show(); [System.Windows.Forms.Application]::DoEvents()
    $previewBtn.PerformClick()
    Write-Host "after preview: copy button enabled = $($copyBtn.Enabled); rows = $($list.Items.Count); status = $($status.Text)"
    Save-Shot 'preview.png'
    $copyBtn.PerformClick()
    Write-Host "after copy: status = $($status.Text)"
    Save-Shot 'after-copy.png'
    $form.Close(); exit 0
}
[void]$form.ShowDialog()
