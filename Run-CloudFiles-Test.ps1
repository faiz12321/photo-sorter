# Creates REAL Windows cloud-file placeholders (the same Windows Cloud Files mechanism OneDrive uses)
# with a tiny test sync provider, then checks Photo Sorter leaves them alone.
# This is NOT OneDrive itself: no OneDrive client, account, or sync states are involved.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PhotoSorter.Core.ps1')
$script:pass = 0; $script:fail = 0
function Check([string]$Name, [bool]$Cond) { if ($Cond) { $script:pass++; Write-Host "PASS  $Name" } else { $script:fail++; Write-Host "FAIL  $Name" } }
function Info([string]$Msg) { Write-Host "INFO  $Msg" }
Info ("PowerShell " + $PSVersionTable.PSVersion + " on " + [Environment]::OSVersion.VersionString)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Cf {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct SyncReg { public uint StructSize; public string ProviderName; public string ProviderVersion; public IntPtr SyncRootIdentity; public uint SyncRootIdentityLength; public IntPtr FileIdentity; public uint FileIdentityLength; public Guid ProviderId; }
  [StructLayout(LayoutKind.Sequential)]
  public struct SyncPol { public uint StructSize; public ushort HydPrimary; public ushort HydModifier; public ushort PopPrimary; public ushort PopModifier; public uint InSync; public uint HardLink; public uint PlaceholderMgmt; }
  [StructLayout(LayoutKind.Sequential)]
  public struct Meta { public long Creation; public long LastAccess; public long LastWrite; public long Change; public uint Attr; public long Size; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct PhInfo { public string RelativeFileName; public Meta Fs; public IntPtr FileIdentity; public uint FileIdentityLength; public uint Flags; public int Result; public long CreateUsn; }
  [DllImport("cldapi.dll", CharSet=CharSet.Unicode)] public static extern int CfRegisterSyncRoot(string path, ref SyncReg reg, ref SyncPol pol, uint flags);
  [DllImport("cldapi.dll", CharSet=CharSet.Unicode)] public static extern int CfCreatePlaceholders(string basePath, [In, Out] PhInfo[] entries, uint count, uint flags, out uint processed);
  [DllImport("cldapi.dll")] public static extern int CfConvertToPlaceholder(IntPtr h, IntPtr id, uint idLen, uint flags, IntPtr usn, IntPtr ov);
  [DllImport("cldapi.dll", CharSet=CharSet.Unicode)] public static extern int CfUnregisterSyncRoot(string path);
}
'@

$root = Join-Path $env:RUNNER_TEMP ("cf-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$sync = Join-Path $root 'SyncRoot'; $dst = Join-Path $root 'Sorted'
New-Item -ItemType Directory -Path $sync, $dst | Out-Null
$fsType = (New-Object System.IO.DriveInfo ([IO.Path]::GetPathRoot($root))).DriveFormat
Info "test folder drive format: $fsType"

$registered = $false
foreach ($size in @(24, 20)) {
    $reg = New-Object Cf+SyncReg; $reg.StructSize = [uint32][Runtime.InteropServices.Marshal]::SizeOf([type]'Cf+SyncReg')
    $reg.ProviderName = 'PhotoSorterTestProvider'; $reg.ProviderVersion = '1.0'; $reg.ProviderId = [guid]::NewGuid()
    $pol = New-Object Cf+SyncPol; $pol.StructSize = [uint32]$size; $pol.HydPrimary = 1; $pol.PopPrimary = 2
    $hr = [Cf]::CfRegisterSyncRoot($sync, [ref]$reg, [ref]$pol, 2)   # 2 = update if it exists
    Info ("CfRegisterSyncRoot (policy size $size) HRESULT = 0x{0:X8}" -f $hr)
    if ($hr -eq 0) { $registered = $true; break }
}
Check 'real sync root registered with Windows' $registered
if (-not $registered) { Info 'Cloud Files API not usable on this machine; cannot create real placeholders.'; Write-Host "$script:pass passed, $script:fail failed"; exit 1 }

# Placeholders: two photos, plus one inside a sub folder.
New-Item -ItemType Directory -Path (Join-Path $sync 'trip') | Out-Null
$names = @('cloud-only-1.jpg', 'cloud-only-2.jpg')
$mk = { param($rel, $len)
    $e = New-Object Cf+PhInfo; $e.RelativeFileName = $rel
    $e.Fs = New-Object Cf+Meta; $e.Fs.Attr = 0x80; $e.Fs.Size = $len
    $t = [DateTime]::UtcNow.ToFileTimeUtc(); $e.Fs.Creation = $t; $e.Fs.LastAccess = $t; $e.Fs.LastWrite = $t; $e.Fs.Change = $t
    $id = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($rel); $e.FileIdentity = $id; $e.FileIdentityLength = [uint32](2 * $rel.Length)
    $e.Flags = 0; return $e }
$entries = [Cf+PhInfo[]]@((& $mk $names[0] 5MB), (& $mk $names[1] 3MB))
$done = [uint32]0
$hr = [Cf]::CfCreatePlaceholders($sync, $entries, 2, 0, [ref]$done)
Info ("CfCreatePlaceholders HRESULT = 0x{0:X8}, created $done" -f $hr)
$entries2 = [Cf+PhInfo[]]@((& $mk 'beach.jpg' 4MB))
$done2 = [uint32]0
$hr2 = [Cf]::CfCreatePlaceholders((Join-Path $sync 'trip'), $entries2, 1, 0, [ref]$done2)
Info ("CfCreatePlaceholders (sub folder) HRESULT = 0x{0:X8}, created $done2" -f $hr2)
Check 'real placeholders created' ($hr -eq 0 -and $done -eq 2 -and $hr2 -eq 0 -and $done2 -eq 1)

# A normal local photo in the same folder, so the run has something to copy.
[IO.File]::WriteAllBytes((Join-Path $sync 'local-real.jpg'), [byte[]](1..200))
# A downloaded ("always keep on this device") style file: a normal file converted into an in-sync placeholder that has its data.
$hyd = Join-Path $sync 'downloaded.jpg'
[IO.File]::WriteAllBytes($hyd, [byte[]](1..200))
$fh = [IO.File]::Open($hyd, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try { $hrc = [Cf]::CfConvertToPlaceholder($fh.SafeFileHandle.DangerousGetHandle(), [IntPtr]::Zero, 0, 1, [IntPtr]::Zero, [IntPtr]::Zero) } finally { $fh.Dispose() }
Info ("CfConvertToPlaceholder HRESULT = 0x{0:X8}" -f $hrc)
$hi = Get-Item -LiteralPath $hyd -Force
Info ("downloaded.jpg (has its data) attributes: " + $hi.Attributes + (' (0x{0:X})' -f [int]$hi.Attributes) + ", size " + $hi.Length)
foreach ($p in @('cloud-only-1.jpg', 'trip\beach.jpg')) {
    $it = Get-Item -LiteralPath (Join-Path $sync $p) -Force
    Info ("$p attributes: " + $it.Attributes + (' (0x{0:X})' -f [int]$it.Attributes) + ", size " + $it.Length)
}

$plan = New-SortPlan -Source $sync -Dest $dst
$copyCount = @($plan.Items | Where-Object { $_.Action -eq 'Copy' }).Count
$skipOnline = @($plan.Skipped | Where-Object { $_.Reason -like 'Online-only*' }).Count
$skipLink = @($plan.Skipped | Where-Object { $_.Reason -like 'Shortcut*' }).Count
$hydItem = @($plan.Items | Where-Object { $_.Source -like '*downloaded.jpg' })
$hydSkip = @($plan.Skipped | Where-Object { $_.Path -like '*downloaded.jpg' })
Info ("downloaded.jpg: planned=" + $hydItem.Count + " action=" + $(if ($hydItem.Count) { $hydItem[0].Action } else { '-' }) + "; skipped=" + $hydSkip.Count + $(if ($hydSkip.Count) { ' reason=' + $hydSkip[0].Reason } else { '' }))
$copyCount = $copyCount - $hydItem.Count
$skipOnline = $skipOnline - @($hydSkip | Where-Object { $_.Reason -like 'Online-only*' }).Count
$skipLink = $skipLink - @($hydSkip | Where-Object { $_.Reason -like 'Shortcut*' }).Count
Info "plan: copy=$copyCount, skipped as online-only=$skipOnline, skipped as link=$skipLink"
Check 'a downloaded (has its data) placeholder is NOT treated as a link' ($hydSkip.Count -eq 0)
Check 'a downloaded placeholder is planned for copy' ($hydItem.Count -eq 1 -and $hydItem[0].Action -eq 'Copy')
Check 'real placeholders are all skipped (3 of 3)' (($skipOnline + $skipLink) -eq 3)
Check 'real placeholders are reported as online-only' ($skipOnline -eq 3)
Check 'only the genuine local photo is planned for copy' ($copyCount -eq 1)
$res = Invoke-SortPlan $plan
Check 'copy run has no failures' ($res.Failed.Count -eq 0)
# Nothing was downloaded: placeholders still carry their cloud/offline bits and size.
$still = @(Get-ChildItem -LiteralPath $sync -Recurse -Force -File | Where-Object { $_.Name -ne 'local-real.jpg' })
Check 'placeholders still online-only after the run (not downloaded)' (@($still | Where-Object { ([int]$_.Attributes -band 0x441000) -ne 0 }).Count -eq 3)
Check 'nothing extra appeared in the destination' (@(Get-ChildItem -LiteralPath $dst -Recurse -File | Where-Object { $_.FullName -notlike '*PhotoSorter-logs*' }).Count -eq 1)

try { [void][Cf]::CfUnregisterSyncRoot($sync) } catch { }
Write-Host "$script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { exit 1 }
