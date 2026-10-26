<#
.SYNOPSIS
  setup.ps1 — native Windows installer for the components this repo
  supports on Windows (winget packages and official vendor installers).

.DESCRIPTION
  The Windows counterpart of scripts/setup.sh, with the same selection
  contract:
    - Interactive runs confirm each component (default yes); selection
      flags only pre-scope the menu.
    - Unattended runs (-AssumeYes, or DEV_SETUP_ASSUME_YES=1) install
      exactly the selected components, or everything with no selection.
  Every component has a matching --<component> flag, and -Modules takes a
  comma-separated list. Components the shared catalog has only on Linux
  (nvidia-driver, ik-llama-cpp, ktransformers, vllm) are warned about and
  skipped. Each install is idempotent: winget upgrades in place or no-ops.

  Run from PowerShell (Windows PowerShell 5.1 or PowerShell 7); an
  elevated prompt avoids one UAC confirmation per machine-wide package:
    powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1 --7zip --notepad-plus-plus
    powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1 -AssumeYes -Modules git-bash,winscp

  The Linux toolchain (setup.sh) runs under WSL2 Ubuntu with --os ubuntu.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
  # Comma-separated components (also accepts a PowerShell array).
  [string[]]$Modules = @(),
  # Accept every prompt (same as DEV_SETUP_ASSUME_YES=1).
  [switch]$AssumeYes,
  # Print the available components and exit.
  [switch]$List,
  [switch]$Help,
  # --<component> flags, setup.sh style.
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Flags = @()
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\windows.ps1')
. (Join-Path $PSScriptRoot 'lib\windows-components.ps1')
if ($AssumeYes) { $script:DevSetupAssumeYes = $true }

function Show-Usage {
  Write-Host 'Usage: setup.ps1 [-Modules LIST] [--<component> ...] [-AssumeYes] [-List]'
  Write-Host '  Interactive runs confirm each component (default yes); selection flags'
  Write-Host '  pre-scope which components are offered. Unattended runs (-AssumeYes or'
  Write-Host '  DEV_SETUP_ASSUME_YES=1) install exactly the selection, or everything.'
  Write-Host ('  Component flags: ' + (($script:Components.Keys | ForEach-Object { "--$_" }) -join ' '))
  Write-Host ('  Linux-only (warned + skipped here): ' + ($script:WindowsUnsupported.Keys -join ' '))
}

# ---- argument parsing (shared with uninstall.ps1 semantics) ----------------
$requested = New-Object System.Collections.Generic.List[string]
foreach ($m in $Modules) { foreach ($part in ($m -split ',')) { if ($part.Trim()) { $requested.Add($part.Trim()) } } }
foreach ($f in $Flags) {
  if ($f -notlike '--*') { Write-Fail "Unknown argument: $f"; Show-Usage; exit 2 }
  $requested.Add($f.Substring(2))
}
if ($Help) { Show-Usage; exit 0 }
if ($List) { $script:Components.Keys; exit 0 }
foreach ($r in $requested) {
  if (-not $script:Components.Contains($r) -and -not $script:WindowsUnsupported.Contains($r)) {
    Write-Fail "Unknown component: $r (see -List)"; Show-Usage; exit 2
  }
}

if (-not (Test-IsWindows)) {
  Write-Fail 'setup.ps1 is the native Windows installer — on Linux run scripts/setup.sh.'
  exit 1
}

Write-Section 'Development environment setup (Windows)'
Write-Log "Machine: $env:COMPUTERNAME — $([Environment]::OSVersion.VersionString)"
if (Test-NvidiaGpu) { Write-Log 'GPU:     NVIDIA detected' }

# ---- component selection -----------------------------------------------------
Write-Section 'Select components'
$candidates = @()
if ($requested.Count -gt 0) {
  foreach ($name in $script:WindowsUnsupported.Keys) {
    if ($requested.Contains($name)) {
      Write-Warn "${name}: not supported on windows — $($script:WindowsUnsupported[$name])"
    }
  }
  $candidates = @($script:Components.Keys | Where-Object { $requested.Contains($_) })
  Write-Log "Selected on the command line: $($candidates -join ' ')"
} else {
  $candidates = @($script:Components.Keys)
}
$selected = @()
foreach ($name in $candidates) {
  if (Confirm-Choice "Install $($script:Components[$name].Describe)?" 'y') { $selected += $name }
}
if ($selected.Count -eq 0) { Write-Warn 'Nothing selected — exiting.'; exit 0 }

Assert-Winget
if (-not (Test-IsAdmin)) {
  Write-Warn 'Not elevated: machine-wide packages will each ask for UAC confirmation (run from an elevated PowerShell to avoid that).'
}

# ---- install -------------------------------------------------------------------
Write-Section "Installing: $($selected -join ' ')"
$failed = @()
foreach ($name in $selected) {
  Write-Section $script:Components[$name].Describe
  try {
    Invoke-ComponentAction -Name $name -Action Install
    Update-SessionPath
  } catch {
    $failed += $name
    Write-Fail "Component '$name' failed: $($_.Exception.Message) — continuing with the rest."
  }
}

# ---- summary -------------------------------------------------------------------
Write-Section 'Summary'
foreach ($name in $selected) {
  if ($failed -contains $name) { Write-Fail "${name}: FAILED (re-run: .\scripts\setup.ps1 --$name)" }
  else { Write-Ok "${name}: installed" }
}
if ($failed.Count -gt 0) { exit 1 }
Write-Log 'Done. Open a new terminal so PATH updates take effect.'
# Explicit: a script that just ends hands its caller the last native
# command's exit code (e.g. winget's "no upgrade available").
exit 0
