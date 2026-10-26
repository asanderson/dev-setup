<#
.SYNOPSIS
  uninstall.ps1 — remove components the native Windows installer
  (scripts/setup.ps1) set up.

.DESCRIPTION
  Mirrors scripts/uninstall.sh: ALL components are candidates by default;
  interactive runs confirm each (default yes), unattended runs
  (-AssumeYes or DEV_SETUP_ASSUME_YES=1) remove exactly the selection, or
  everything with no selection flags. Components uninstall in reverse
  install order. User data (configs, credentials, sessions, models,
  Cygwin's root) is KEPT unless -PurgeData is passed; virtual machines are
  never deleted.
    powershell -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 --winscp
    powershell -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 -AssumeYes -PurgeData
#>
[CmdletBinding(PositionalBinding = $false)]
param(
  [string[]]$Modules = @(),
  [switch]$AssumeYes,
  # Also remove user data (configs, credentials, sessions, models).
  [switch]$PurgeData,
  [switch]$List,
  [switch]$Help,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Flags = @()
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows.ps1')
. (Join-Path $PSScriptRoot 'lib\windows-components.ps1')
if ($AssumeYes) { $script:DevSetupAssumeYes = $true }
$script:DevSetupPurgeData = [bool]$PurgeData

function Show-Usage {
  Write-Host 'Usage: uninstall.ps1 [-Modules LIST] [--<component> ...] [-AssumeYes] [-PurgeData] [-List]'
  Write-Host '  Default: ALL components are candidates. Interactive runs confirm each'
  Write-Host '  (default yes); unattended runs remove exactly the selection, or everything.'
  Write-Host ('  Component flags: ' + (($script:Components.Keys | ForEach-Object { "--$_" }) -join ' '))
}

$requested = New-Object System.Collections.Generic.List[string]
foreach ($m in $Modules) { foreach ($part in ($m -split ',')) { if ($part.Trim()) { $requested.Add($part.Trim()) } } }
foreach ($f in $Flags) {
  if ($f -notlike '--*') { Write-Fail "Unknown argument: $f"; Show-Usage; exit 2 }
  $requested.Add($f.Substring(2))
}
if ($Help) { Show-Usage; exit 0 }
if ($List) { $script:Components.Keys; exit 0 }
foreach ($r in $requested) {
  if (-not $script:Components.Contains($r)) { Write-Fail "Unknown component: $r (see -List)"; Show-Usage; exit 2 }
}

if (-not (Test-IsWindows)) {
  Write-Fail 'uninstall.ps1 is the native Windows uninstaller — on Linux run scripts/uninstall.sh.'
  exit 1
}

Write-Section 'Component removal (Windows)'
if ($script:DevSetupPurgeData) { Write-Warn '-PurgeData: user data (configs, credentials, sessions, models) will be removed too.' }
else { Write-Log 'User data is kept (pass -PurgeData to remove it as well).' }

$names = @($script:Components.Keys)
[array]::Reverse($names)
$candidates = @($names | Where-Object { $requested.Count -eq 0 -or $requested.Contains($_) })
if ($requested.Count -gt 0) { Write-Log "Selected on the command line: $($candidates -join ' ')" }
$selected = @()
foreach ($name in $candidates) {
  if (Confirm-Choice "Uninstall $($script:Components[$name].Describe)?" 'y') { $selected += $name }
}
if ($selected.Count -eq 0) { Write-Warn 'Nothing selected — exiting.'; exit 0 }

Assert-Winget
Write-Section "Uninstalling: $($selected -join ' ')"
$failed = @()
foreach ($name in $selected) {
  Write-Section "Uninstall: $name"
  try {
    Invoke-ComponentAction -Name $name -Action Uninstall
  } catch {
    $failed += $name
    Write-Fail "Uninstall of '$name' failed: $($_.Exception.Message) — continuing with the rest."
  }
}

Write-Section 'Summary'
foreach ($name in $selected) {
  if ($failed -contains $name) { Write-Fail "${name}: FAILED (re-run: .\scripts\uninstall.ps1 --$name)" }
  else { Write-Ok "${name}: uninstalled" }
}
if ($failed.Count -gt 0) { exit 1 }
Write-Log 'Done. Open a new terminal so removed PATH entries disappear.'
# Explicit: a script that just ends hands its caller the last native
# command's exit code (e.g. winget's "no upgrade available").
exit 0
