# Photo Sorter - core logic. Works in Windows PowerShell 5.1 and PowerShell 7.
# Copies photos into Year\Month folders by Date Taken. Never moves, deletes or overwrites anything.
Set-StrictMode -Version 2.0

if (-not ('PhotoSorterExif' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public static class PhotoSorterExif {
    // Returns the EXIF "date taken" of a JPEG, or null if it cannot be read.
    public static string ReadJpegDateTaken(string path) {
        try {
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)) {
                byte[] head = new byte[2];
                if (fs.Read(head, 0, 2) != 2 || head[0] != 0xFF || head[1] != 0xD8) return null;
                while (true) {
                    int b = fs.ReadByte();
                    if (b < 0) return null;
                    if (b != 0xFF) continue;
                    int marker = fs.ReadByte();
                    while (marker == 0xFF) marker = fs.ReadByte();
                    if (marker < 0 || marker == 0xDA || marker == 0xD9) return null;
                    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
                    int hi = fs.ReadByte(); int lo = fs.ReadByte();
                    if (hi < 0 || lo < 0) return null;
                    int len = (hi << 8) | lo;
                    if (len < 2) return null;
                    int dataLen = len - 2;
                    if (marker != 0xE1) { fs.Seek(dataLen, SeekOrigin.Current); continue; }
                    if (dataLen < 14 || dataLen > 1048576) { fs.Seek(dataLen, SeekOrigin.Current); continue; }
                    byte[] seg = new byte[dataLen];
                    int got = 0;
                    while (got < dataLen) { int r = fs.Read(seg, got, dataLen - got); if (r <= 0) return null; got += r; }
                    if (seg[0] != 'E' || seg[1] != 'x' || seg[2] != 'i' || seg[3] != 'f' || seg[4] != 0 || seg[5] != 0) continue;
                    return FromTiff(seg, 6);
                }
            }
        } catch { return null; }
    }
    // HEIC/HEIF: the EXIF block sits inside the file; look for its header near the start.
    public static string ReadHeicDateTaken(string path) {
        try {
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)) {
                int max = (int)Math.Min(fs.Length, 4194304L);
                byte[] d = new byte[max]; int got = 0;
                while (got < max) { int r = fs.Read(d, got, max - got); if (r <= 0) break; got += r; }
                for (int i = 0; i + 12 < got; i++) {
                    if (d[i] == 'E' && d[i+1] == 'x' && d[i+2] == 'i' && d[i+3] == 'f' && d[i+4] == 0 && d[i+5] == 0) {
                        bool ii = d[i+6] == 'I' && d[i+7] == 'I' && d[i+8] == 42 && d[i+9] == 0;
                        bool mm = d[i+6] == 'M' && d[i+7] == 'M' && d[i+8] == 0 && d[i+9] == 42;
                        if (ii || mm) {
                            byte[] sub = new byte[got - (i + 6)];
                            Array.Copy(d, i + 6, sub, 0, sub.Length);
                            string r = FromTiff(sub, 0);
                            if (r != null) return r;
                        }
                    }
                }
                return null;
            }
        } catch { return null; }
    }
    // MP4/MOV/M4V/3GP: creation time from the movie header (UTC), seconds since 1904-01-01. 0 means not set.
    public static string ReadMp4Created(string path) {
        try {
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)) {
                long end = fs.Length; long pos = 0;
                while (pos + 8 <= end) {
                    fs.Seek(pos, SeekOrigin.Begin);
                    byte[] h = new byte[8]; if (fs.Read(h, 0, 8) != 8) return null;
                    long size = ((long)h[0] << 24) | ((long)h[1] << 16) | ((long)h[2] << 8) | h[3];
                    string type = Encoding.ASCII.GetString(h, 4, 4);
                    long hdr = 8;
                    if (size == 1) { byte[] e = new byte[8]; if (fs.Read(e, 0, 8) != 8) return null; size = 0; for (int k = 0; k < 8; k++) size = (size << 8) | e[k]; hdr = 16; }
                    else if (size == 0) size = end - pos;
                    if (size < hdr) return null;
                    if (type == "moov") { end = Math.Min(end, pos + size); pos += hdr; continue; }
                    if (type == "mvhd") {
                        byte[] m = new byte[20]; if (fs.Read(m, 0, 20) < 8) return null;
                        long secs;
                        if (m[0] == 1) { secs = 0; for (int k = 0; k < 8; k++) secs = (secs << 8) | m[4 + k]; }
                        else secs = ((long)m[4] << 24) | ((long)m[5] << 16) | ((long)m[6] << 8) | m[7];
                        if (secs <= 0) return null;
                        DateTime dt = new DateTime(1904, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(secs).ToLocalTime();
                        if (dt.Year < 1990 || dt.Year > 2100) return null;
                        return dt.ToString("yyyy:MM:dd HH:mm:ss");
                    }
                    pos += size;
                }
                return null;
            }
        } catch { return null; }
    }
    static int U16(byte[] d, int o, bool le) { if (o < 0 || o + 2 > d.Length) throw new Exception(); return le ? d[o] | (d[o+1] << 8) : (d[o] << 8) | d[o+1]; }
    static long U32(byte[] d, int o, bool le) { if (o < 0 || o + 4 > d.Length) throw new Exception(); return le ? (long)d[o] | ((long)d[o+1] << 8) | ((long)d[o+2] << 16) | ((long)d[o+3] << 24) : ((long)d[o] << 24) | ((long)d[o+1] << 16) | ((long)d[o+2] << 8) | (long)d[o+3]; }
    static string FromTiff(byte[] d, int t) {
        try {
            bool le;
            if (d[t] == 'I' && d[t+1] == 'I') le = true; else if (d[t] == 'M' && d[t+1] == 'M') le = false; else return null;
            long ifd0 = U32(d, t + 4, le);
            long exifPtr = -1; string modified = null;
            ScanIfd(d, t, (int)ifd0, le, ref exifPtr, ref modified);
            string original = null; string digitized = null;
            if (exifPtr > 0) {
                ScanExif(d, t, (int)exifPtr, le, ref original, ref digitized);
            }
            string r = original ?? digitized ?? modified;
            return Valid(r) ? r : null;
        } catch { return null; }
    }
    static void ScanIfd(byte[] d, int t, int ifd, bool le, ref long exifPtr, ref string modified) {
        int o = t + ifd; int n = U16(d, o, le);
        for (int i = 0; i < n && i < 512; i++) {
            int e = o + 2 + i * 12; int tag = U16(d, e, le);
            if (tag == 0x8769) exifPtr = U32(d, e + 8, le);
            else if (tag == 0x0132) modified = Ascii(d, t, e, le);
        }
    }
    static void ScanExif(byte[] d, int t, int ifd, bool le, ref string original, ref string digitized) {
        int o = t + ifd; int n = U16(d, o, le);
        for (int i = 0; i < n && i < 512; i++) {
            int e = o + 2 + i * 12; int tag = U16(d, e, le);
            if (tag == 0x9003) original = Ascii(d, t, e, le);
            else if (tag == 0x9004) digitized = Ascii(d, t, e, le);
        }
    }
    static string Ascii(byte[] d, int t, int e, bool le) {
        long count = U32(d, e + 4, le);
        if (count < 19 || count > 64) return null;
        int start = count <= 4 ? e + 8 : t + (int)U32(d, e + 8, le);
        if (start < 0 || start + 19 > d.Length) return null;
        return Encoding.ASCII.GetString(d, start, 19);
    }
    static bool Valid(string s) {
        if (s == null || s.Length != 19) return false;
        int y, mo, da;
        if (!int.TryParse(s.Substring(0, 4), out y) || !int.TryParse(s.Substring(5, 2), out mo) || !int.TryParse(s.Substring(8, 2), out da)) return false;
        return y >= 1900 && y <= 2100 && mo >= 1 && mo <= 12 && da >= 1 && da <= 31;
    }
}
'@
}

$script:MediaExtensions = @('.jpg','.jpeg','.png','.gif','.bmp','.tif','.tiff','.webp','.heic','.heif','.dng','.cr2','.nef','.arw','.mp4','.mov','.m4v','.avi','.mkv','.3gp')

function Get-FullPathNormalized([string]$Path) {
    $p = [System.IO.Path]::GetFullPath($Path)
    return $p.TrimEnd([char]'\', [char]'/')
}

function Test-PathInside([string]$Child, [string]$Parent) {
    $c = (Get-FullPathNormalized $Child); $p = (Get-FullPathNormalized $Parent)
    $cmp = [System.StringComparison]::OrdinalIgnoreCase
    if ($c.Equals($p, $cmp)) { return $true }
    $sep = [string][System.IO.Path]::DirectorySeparatorChar
    return $c.StartsWith($p + $sep, $cmp)
}

function Test-PathThroughLink([string]$Path) {
    # True when any folder on the way to $Path (that already exists) is a link or junction.
    $p = Get-FullPathNormalized $Path
    while ($p) {
        if (Test-Path -LiteralPath $p) {
            $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
            if ($it -and (Test-IsRealLink $it)) { return $true }
        }
        $parent = [System.IO.Path]::GetDirectoryName($p)
        if (-not $parent -or $parent -eq $p) { break }
        $p = $parent
    }
    return $false
}

function Test-FolderChoice([string]$Source, [string]$Dest) {
    # Returns an error message, or $null when the choice is safe.
    if (-not $Source -or -not (Test-Path -LiteralPath $Source -PathType Container)) { return 'The photo folder does not exist.' }
    if (-not $Dest) { return 'Choose a destination folder.' }
    if (Test-PathInside $Dest $Source) { return 'The destination cannot be the same as, or inside, the photo folder.' }
    if (Test-PathThroughLink $Dest) { return 'The destination goes through a shortcut or junction. Pick a normal folder so the copies cannot end up inside your photo folder.' }
    $blocked = @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) | Where-Object { $_ }
    foreach ($b in $blocked) { if ((Test-PathInside $Dest $b) -or (Test-PathInside $Source $b)) { return 'System folders are not allowed.' } }
    $root = [System.IO.Path]::GetPathRoot((Get-FullPathNormalized $Dest))
    if ((Get-FullPathNormalized $Dest) -eq (Get-FullPathNormalized $root)) { return 'Pick a folder, not a whole drive, as the destination.' }
    return $null
}

function Test-IsRealLink($Item) {
    # True for symlinks and junctions. Cloud-file placeholders (OneDrive and similar) are also reparse points,
    # but they are ordinary files/folders to the user, so they are not "links".
    if (-not ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
    $p = $Item.PSObject.Properties['LinkType']
    if ($p -and $p.Value) { return $true }
    return $false
}

function Get-MediaFiles([string]$Root) {
    # Manual walk so symlinks and junctions are never followed.
    $skipped = New-Object System.Collections.ArrayList
    $files = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    $stack.Push((Get-Item -LiteralPath $Root -Force))
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try { $items = @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction Stop) }
        catch { [void]$skipped.Add([pscustomobject]@{ Path = $dir.FullName; Reason = 'Cannot open folder' }); continue }
        foreach ($it in $items) {
            # Online-only files (OneDrive and similar): reading them would download them, so they are left alone.
            if (([int]$it.Attributes -band 0x441000) -ne 0) { [void]$skipped.Add([pscustomobject]@{ Path = $it.FullName; Reason = 'Online-only file (not downloaded)' }); continue }
            if (Test-IsRealLink $it) { [void]$skipped.Add([pscustomobject]@{ Path = $it.FullName; Reason = 'Shortcut/link, not followed' }); continue }
            if ($it.PSIsContainer) { $stack.Push($it); continue }
            if (($it.Attributes -band [IO.FileAttributes]::Hidden) -or ($it.Attributes -band [IO.FileAttributes]::System)) { [void]$skipped.Add([pscustomobject]@{ Path = $it.FullName; Reason = 'Hidden or system file' }); continue }
            if ($script:MediaExtensions -notcontains $it.Extension.ToLowerInvariant()) { continue }
            [void]$files.Add($it)
        }
    }
    return [pscustomobject]@{ Files = @($files | Sort-Object FullName); Skipped = @($skipped) }
}

function Get-Sha256([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($fs))).Replace('-', '') }
    finally { $fs.Dispose(); $sha.Dispose() }
}

function Get-TakenDate($File) {
    $ext = $File.Extension.ToLowerInvariant()
    $s = $null; $label = 'Date taken'
    if ($ext -eq '.jpg' -or $ext -eq '.jpeg') { $s = [PhotoSorterExif]::ReadJpegDateTaken($File.FullName) }
    elseif ($ext -eq '.heic' -or $ext -eq '.heif') { $s = [PhotoSorterExif]::ReadHeicDateTaken($File.FullName) }
    elseif ($ext -eq '.mp4' -or $ext -eq '.mov' -or $ext -eq '.m4v' -or $ext -eq '.3gp') { $s = [PhotoSorterExif]::ReadMp4Created($File.FullName); $label = 'Video created' }
    if ($s) { return [pscustomobject]@{ Date = [datetime]::ParseExact($s, 'yyyy:MM:dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture); Source = $label } }
    return [pscustomobject]@{ Date = $File.LastWriteTime; Source = 'File date' }
}

function New-SortPlan {
    param([string]$Source, [string]$Dest)
    $err = Test-FolderChoice $Source $Dest
    if ($err) { throw $err }
    $scan = Get-MediaFiles $Source
    $destFull = Get-FullPathNormalized $Dest
    $plan = New-Object System.Collections.ArrayList
    $planned = @{}          # target path (lowercase) -> hash, for collisions inside this run
    $seenHash = @{}         # hash -> first source path
    foreach ($f in $scan.Files) {
        $hash = $null
        try { $hash = Get-Sha256 $f.FullName } catch { [void]$plan.Add([pscustomobject]@{ Source = $f.FullName; Target = ''; Action = 'Skip'; Reason = 'Cannot read file'; DateFrom = ''; Hash = '' }); continue }
        if ($seenHash.ContainsKey($hash)) {
            [void]$plan.Add([pscustomobject]@{ Source = $f.FullName; Target = ''; Action = 'Duplicate'; Reason = 'Identical to ' + $seenHash[$hash]; DateFrom = ''; Hash = $hash }); continue
        }
        $seenHash[$hash] = $f.FullName
        $td = Get-TakenDate $f
        $folder = Join-Path (Join-Path $destFull $td.Date.ToString('yyyy')) $td.Date.ToString('MM')
        $name = $f.Name; $n = 1; $target = $null; $action = 'Copy'; $reason = ''
        while ($true) {
            $cand = Join-Path $folder $name
            $key = $cand.ToLowerInvariant()
            if (Test-Path -LiteralPath $cand) {
                if ((Get-Sha256 $cand) -eq $hash) { $action = 'AlreadyThere'; $reason = 'Same file already in destination'; $target = $cand; break }
            } elseif (-not $planned.ContainsKey($key)) { $target = $cand; break }
            $n++; $name = [IO.Path]::GetFileNameWithoutExtension($f.Name) + " ($n)" + $f.Extension
            $reason = 'Renamed to avoid a name clash'
        }
        if ($action -eq 'Copy' -and $target.Length -ge 255) { [void]$plan.Add([pscustomobject]@{ Source = $f.FullName; Target = $target; Action = 'Skip'; Reason = 'Destination path too long'; DateFrom = $td.Source; Hash = $hash }); continue }
        if ($action -eq 'Copy') { $planned[$target.ToLowerInvariant()] = $hash }
        [void]$plan.Add([pscustomobject]@{ Source = $f.FullName; Target = $target; Action = $action; Reason = $reason; DateFrom = $td.Source; Hash = $hash })
    }
    return [pscustomobject]@{ Source = (Get-FullPathNormalized $Source); Dest = $destFull; Items = @($plan); Skipped = $scan.Skipped }
}

function Get-PlanSummary($Plan) {
    $i = @($Plan.Items)
    return [pscustomobject]@{
        ToCopy = @($i | Where-Object { $_.Action -eq 'Copy' }).Count
        Renamed = @($i | Where-Object { $_.Action -eq 'Copy' -and $_.Reason }).Count
        FromFileDate = @($i | Where-Object { $_.Action -eq 'Copy' -and $_.DateFrom -eq 'File date' }).Count
        Duplicates = @($i | Where-Object { $_.Action -eq 'Duplicate' }).Count
        AlreadyThere = @($i | Where-Object { $_.Action -eq 'AlreadyThere' }).Count
        Skipped = @($i | Where-Object { $_.Action -eq 'Skip' }).Count + @($Plan.Skipped).Count
    }
}

function Invoke-SortPlan {
    param($Plan)
    $logDir = Join-Path $Plan.Dest 'PhotoSorter-logs'
    $createdDirs = New-Object System.Collections.ArrayList
    $createdFiles = New-Object System.Collections.ArrayList
    $failed = New-Object System.Collections.ArrayList
    $mk = {
        param([string]$d)
        $missing = New-Object System.Collections.ArrayList
        $cur = $d
        while ($cur -and -not (Test-Path -LiteralPath $cur)) { [void]$missing.Add($cur); $cur = Split-Path -Parent $cur }
        for ($k = $missing.Count - 1; $k -ge 0; $k--) { [void][IO.Directory]::CreateDirectory($missing[$k]); [void]$createdDirs.Add($missing[$k]) }
    }
    $logPath = $null
    try {
        & $mk $Plan.Dest
        & $mk $logDir
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $logPath = Join-Path $logDir "undo-$stamp.json"
        foreach ($it in $Plan.Items) {
            if ($it.Action -ne 'Copy') { continue }
            try {
                & $mk (Split-Path -Parent $it.Target)
                [IO.File]::Copy($it.Source, $it.Target, $false)   # $false = never overwrite
                if ((Get-Sha256 $it.Target) -ne $it.Hash) {
                    Remove-Item -LiteralPath $it.Target -Force
                    throw 'Copy did not match the original and was removed'
                }
                [void]$createdFiles.Add([pscustomobject]@{ Path = $it.Target; Hash = $it.Hash; From = $it.Source })
            } catch { [void]$failed.Add([pscustomobject]@{ Source = $it.Source; Error = $_.Exception.Message }) }
        }
    } finally {
        if ($logPath) {
            $log = [pscustomobject]@{ Tool = 'PhotoSorter'; Created = (Get-Date).ToString('s'); Source = $Plan.Source; Dest = $Plan.Dest; Files = @($createdFiles); Dirs = @($createdDirs); Failed = @($failed) }
            $log | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $logPath -Encoding UTF8
        }
    }
    return [pscustomobject]@{ Copied = $createdFiles.Count; Failed = @($failed); LogPath = $logPath }
}

function Undo-SortRun {
    param([string]$LogPath)
    $log = Get-Content -LiteralPath $LogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($log.Tool -ne 'PhotoSorter') { throw 'This is not a Photo Sorter log.' }
    $removed = 0; $kept = New-Object System.Collections.ArrayList
    foreach ($f in @($log.Files)) {
        if (-not (Test-Path -LiteralPath $f.Path)) { continue }
        if ((Get-Sha256 $f.Path) -eq $f.Hash) { Remove-Item -LiteralPath $f.Path -Force; $removed++ }
        else { [void]$kept.Add($f.Path) }   # changed since we copied it: not ours to delete
    }
    $dirs = @($log.Dirs) | Sort-Object { $_.Length } -Descending
    foreach ($d in $dirs) {
        if ((Test-Path -LiteralPath $d -PathType Container) -and -not (@(Get-ChildItem -LiteralPath $d -Force).Count) -and ($d -ne (Split-Path -Parent $LogPath))) { Remove-Item -LiteralPath $d -Force }
    }
    return [pscustomobject]@{ Removed = $removed; LeftAlone = @($kept) }
}
