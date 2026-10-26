# windows.ps1 — shared helpers for the native Windows installer
# (scripts/setup.ps1, scripts/uninstall.ps1) and the Windows component
# catalog. Dot-source this file; do not execute it directly.
#
# Windows PowerShell 5.1 compatible (the version every Windows ships):
# no ternaries, no null-coalescing, no pipeline-chain operators.

Set-StrictMode -Version 3.0

# ---------------------------------------------------------------------------
# Logging (same prefixes as scripts/lib/common.sh)
# ---------------------------------------------------------------------------
function Write-Log     { param([string]$Message) Write-Host "[dev-setup] $Message" -ForegroundColor Cyan }
function Write-Ok      { param([string]$Message) Write-Host "[  ok  ] $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "[ warn ] $Message" -ForegroundColor Yellow }
function Write-Fail    { param([string]$Message) Write-Host "[ fail ] $Message" -ForegroundColor Red }
function Write-Section { param([string]$Message) Write-Host ""; Write-Host "==> $Message" -ForegroundColor Blue }

# ---------------------------------------------------------------------------
# Prompting — honors -AssumeYes / DEV_SETUP_ASSUME_YES=1 like confirm() does
# ---------------------------------------------------------------------------
$script:DevSetupAssumeYes = ($env:DEV_SETUP_ASSUME_YES -eq '1')

function Confirm-Choice {
  param([string]$Prompt, [ValidateSet('y', 'n')][string]$Default = 'y')
  if ($script:DevSetupAssumeYes) { Write-Log "$Prompt -> yes (unattended)"; return $true }
  $hint = '[y/N]'
  if ($Default -eq 'y') { $hint = '[Y/n]' }
  while ($true) {
    $reply = "$(Read-Host "$Prompt $hint")".Trim().ToLower()
    if (-not $reply) { $reply = $Default }
    if ($reply -in 'y', 'yes') { return $true }
    if ($reply -in 'n', 'no') { return $false }
    Write-Warn 'Please answer y or n.'
  }
}

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
function Test-IsWindows {
  # $IsWindows exists from PowerShell 6; Windows PowerShell 5.1 only runs on Windows.
  if (Test-Path variable:IsWindows) { return [bool]$IsWindows }
  return ($env:OS -eq 'Windows_NT')
}

function Test-IsAdmin {
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Command { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# Re-read PATH from the registry so tools installed earlier in this run
# (winget, npm, uv) are callable without opening a new shell.
function Update-SessionPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

# Append a directory to the user's PATH (persistent) and this session's.
function Add-UserPath {
  param([string]$Dir)
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $parts = @()
  if ($user) { $parts = $user -split ';' | Where-Object { $_ } }
  if ($parts -notcontains $Dir) {
    [Environment]::SetEnvironmentVariable('Path', (($parts + $Dir) -join ';'), 'User')
    Write-Warn "Added $Dir to your user PATH (new shells pick it up)."
  }
  if (($env:Path -split ';') -notcontains $Dir) { $env:Path = "$env:Path;$Dir" }
}

# Drop every user-PATH entry at or below a directory (installers differ
# on which bin\ subfolder they register).
function Remove-UserPath {
  param([string]$Root)
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not $user) { return }
  $root = $Root.TrimEnd('\')
  $parts = @($user -split ';' | Where-Object { $_ -and -not ($_.TrimEnd('\') -eq $root -or $_ -like "$root\*") })
  [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
}

function Remove-Dir {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
}

# Installed-programs entries (Add/Remove Programs) matching a DisplayName
# wildcard, machine and user scope.
function Get-InstalledApp {
  param([string]$Pattern)
  $keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
  return @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
      Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like $Pattern })
}

# NVIDIA GPU present (any driver state)?
function Test-NvidiaGpu {
  return [bool](@(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'NVIDIA' }).Count)
}

# Fetch a URL to a file (TLS 1.2 forced for Windows PowerShell 5.1).
function Save-Url {
  param([string]$Url, [string]$OutFile)
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $ProgressPreference = 'SilentlyContinue'
  Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

# ---------------------------------------------------------------------------
# winget — idempotent install/uninstall by exact package ID
# ---------------------------------------------------------------------------
# winget exit codes (HRESULTs as signed Int32) that still mean "done":
#   0x8A150061 PACKAGE_ALREADY_INSTALLED, 0x8A15002B UPDATE_NOT_APPLICABLE
#   (installed and current — `winget install` upgrades in place otherwise).
$script:WingetOk = @(0, -1978335135, -1978335189)
#   0x8A150109/0x8A15010A reboot required to finish / for install, 3010 MSI reboot.
$script:WingetReboot = @(-1978334967, -1978334966, 3010)
#   0x8A150014 NO_APPLICATIONS_FOUND (uninstall of something absent).
$script:WingetAbsent = @(-1978335212)

function Assert-Winget {
  if (-not (Test-Command winget)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store (or https://aka.ms/getwinget), then re-run.'
  }
}

function Install-WingetPackage {
  param([string]$Id, [string[]]$Extra = @())
  $wgArgs = @('install', '--id', $Id, '--exact', '--source', 'winget', '--silent',
    '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements') + $Extra
  & winget @wgArgs
  $rc = $LASTEXITCODE
  if ($script:WingetOk -contains $rc) { Write-Ok "$Id installed (current)."; return }
  if ($script:WingetReboot -contains $rc) { Write-Warn "$Id installed; reboot to finish."; return }
  throw "winget install $Id failed (exit $rc)."
}

function Uninstall-WingetPackage {
  param([string]$Id)
  & winget uninstall --id $Id --exact --silent --disable-interactivity --accept-source-agreements
  $rc = $LASTEXITCODE
  if ($script:WingetOk -contains $rc -or $script:WingetReboot -contains $rc) { Write-Ok "$Id removed."; return }
  if ($script:WingetAbsent -contains $rc) { Write-Log "$Id is not installed."; return }
  throw "winget uninstall $Id failed (exit $rc)."
}

# Node.js for the npm-based agent CLIs. The Linux installer has a separate
# nodejs module; on Windows it is pulled in on demand, from winget, the
# first time a component needs it.
function Assert-Npm {
  if (-not (Test-Command npm.cmd)) {
    Write-Log 'Node.js is not installed — installing the LTS line first (winget OpenJS.NodeJS.LTS).'
    Install-WingetPackage -Id 'OpenJS.NodeJS.LTS'
    Update-SessionPath
  }
  if (-not (Test-Command npm.cmd)) { throw 'npm is still not on PATH after installing Node.js — open a new PowerShell and re-run.' }
}

# Run a vendor's PowerShell install script in a child PowerShell (same
# edition as this one), so an `exit` inside it cannot end this installer.
function Invoke-RemoteInstaller {
  param([string]$Url, [string[]]$Arguments = @())
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("dev-setup-" + [guid]::NewGuid().ToString('N') + '.ps1')
  try {
    Save-Url -Url $Url -OutFile $tmp
    $exe = (Get-Process -Id $PID).Path
    & $exe -NoProfile -ExecutionPolicy Bypass -File $tmp @Arguments
    if ($LASTEXITCODE -ne 0) { throw "installer $Url failed (exit $LASTEXITCODE)." }
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
  Update-SessionPath
}

function Invoke-Native {
  # Run a native command and throw on a non-zero exit (PowerShell 5.1 has
  # no $PSNativeCommandUseErrorActionPreference).
  param([string]$Exe, [string[]]$Arguments)
  & $Exe @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') failed (exit $LASTEXITCODE)." }
}
