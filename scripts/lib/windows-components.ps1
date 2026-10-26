# windows-components.ps1 — the native Windows component catalog, in
# install order (uninstalls run in reverse). Names match the Linux modules
# (scripts/modules/*.sh) wherever a component exists on both. Dot-source
# after windows.ps1; do not execute it directly.
#
# An entry either names a winget package ID (Winget = '...', installed and
# removed by exact ID from the winget community source) or carries its own
# Install/Uninstall script blocks for vendors that ship no winget package.

$script:DevSetupPurgeData = $false
$script:Pins = Read-VersionPins (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) (Join-Path 'config' 'versions.env'))

$script:Components = [ordered]@{
  'cuda-toolkit'       = @{
    Describe = 'CUDA Toolkit (NVIDIA, latest — nvcc + libraries; running CUDA code needs the NVIDIA driver)'
    Winget   = 'Nvidia.CUDA'
  }
  'git-bash'           = @{
    Describe = 'Git Bash (Git for Windows: git, git-lfs and the Git Bash shell)'
    Winget   = 'Git.Git'
  }
  'codex'              = @{
    Describe  = "Codex (OpenAI's coding agent CLI, official installer, latest)"
    Install   = {
      $env:CODEX_NON_INTERACTIVE = '1'
      Invoke-RemoteInstaller -Url 'https://chatgpt.com/codex/install.ps1'
      Write-Log "Run 'codex' in a project directory to sign in (ChatGPT plan or OpenAI API key)."
    }
    Uninstall = {
      $dir = Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex'
      Remove-UserPath $dir
      Remove-Dir $dir
      if ($script:DevSetupPurgeData) { Remove-Dir (Join-Path $HOME '.codex'); Write-Log 'Purged ~\.codex (config, credentials, history).' }
      else { Write-Log 'Kept: ~\.codex (config/credentials/history — -PurgeData removes it).' }
    }
  }
  'opencode'           = @{
    Describe  = 'OpenCode (open-source terminal coding agent, npm @opencode/cli, latest)'
    Install   = {
      Assert-Npm
      Invoke-Native 'npm.cmd' @('install', '-g', '@opencode/cli@latest')
      Update-SessionPath
    }
    Uninstall = {
      if (Test-Command npm.cmd) { & npm.cmd uninstall -g '@opencode/cli' | Out-Null }
      if ($script:DevSetupPurgeData) {
        Remove-Dir (Join-Path $HOME '.config\opencode'); Remove-Dir (Join-Path $HOME '.local\share\opencode')
        Write-Log 'Purged OpenCode config and data.'
      }
    }
  }
  'oh-my-pi'           = @{
    Describe  = 'Oh My Pi (omp coding agent, official installer, latest)'
    Install   = { Invoke-RemoteInstaller -Url 'https://omp.sh/install.ps1' }
    Uninstall = {
      # Through cmd: a 2> redirect on a native command under
      # ErrorActionPreference=Stop throws in Windows PowerShell 5.1.
      if (Test-Command bun) { & cmd /c 'bun remove -g @oh-my-pi/pi-coding-agent >nul 2>&1' }
      $dir = Join-Path $env:LOCALAPPDATA 'omp'
      Remove-UserPath $dir
      Remove-Dir $dir
      if ($script:DevSetupPurgeData) { Remove-Dir (Join-Path $HOME '.omp'); Write-Log 'Purged ~\.omp (config, models, sessions).' }
      else { Write-Log 'Kept: ~\.omp (config/models/sessions — -PurgeData removes it).' }
    }
  }
  'hermes-agent'       = @{
    Describe  = 'Hermes Agent (Nous Research agent CLI, official installer)'
    Install   = {
      Invoke-RemoteInstaller -Url 'https://hermes-agent.nousresearch.com/install.ps1' -Arguments @('-NonInteractive')
      Write-Log "Run 'hermes setup' to pick a model provider."
    }
    Uninstall = {
      if (Test-Command hermes) {
        $hArgs = @('uninstall')
        if ($script:DevSetupPurgeData) { $hArgs += '--full' }
        'y' | & hermes @hArgs
      } else { Write-Log 'Hermes Agent is not installed.' }
    }
  }
  'openclaw'           = @{
    Describe  = 'OpenClaw (self-hosted AI assistant gateway, official installer, latest)'
    Install   = {
      Invoke-RemoteInstaller -Url 'https://openclaw.ai/install.ps1' -Arguments @('-NoOnboard')
      Write-Log "Next: 'openclaw onboard --install-daemon', then 'openclaw security audit --deep'."
      Write-Warn 'OpenClaw runs tools on this host with no sandbox by default and trusts its plugins fully:'
      Write-Warn 'keep the gateway on loopback, treat inbound messages and model output as untrusted,'
      Write-Warn 'and use a dedicated user or VM for shared setups.'
    }
    Uninstall = {
      if (Test-Command openclaw) {
        # --state removes ~/.openclaw (the default workspace lives inside
        # it); --all would add --workspace, which deletes configured
        # workspace directories wherever they are — user project dirs too.
        $scopes = @('--service')
        if ($script:DevSetupPurgeData) { $scopes += '--state' }
        & openclaw uninstall @scopes --yes --non-interactive
        if (Test-Command npm.cmd) { & npm.cmd rm -g openclaw | Out-Null }
      } else { Write-Log 'OpenClaw is not installed.' }
    }
  }
  'strata'             = @{
    Describe  = 'Strata (local LLM app + engine, OpenAI/Anthropic-compatible API, STRATA_VERSION pin)'
    # Pinned release (config/versions.env): the installer script is
    # SHA-256 verified, and STRATA_FEED points it at that same release, so
    # the Terminal it installs is the pinned one (checked against the
    # release manifest by the installer itself).
    Install   = {
      $tag = $script:Pins['STRATA_VERSION']
      $env:STRATA_FEED = "https://github.com/Niko1221/Strata/releases/download/$tag"
      Invoke-RemoteInstaller -Url "$env:STRATA_FEED/install.ps1" -Sha256 $script:Pins['STRATA_INSTALL_PS1_SHA256']
      Write-Log "Strata $tag installed. Next: 'strata launch' (fetches the engine + a model), then 'strata connect'."
    }
    Uninstall = {
      $dir = Join-Path $env:LOCALAPPDATA 'Strata'
      Remove-UserPath $dir
      if ($script:DevSetupPurgeData) { Remove-Dir $dir; Write-Log 'Purged %LOCALAPPDATA%\Strata (engine, models).' }
      else { Remove-Dir (Join-Path $dir 'terminal'); Write-Log 'Kept: Strata engine + models (-PurgeData removes them).' }
    }
  }
  '7zip'               = @{
    Describe = '7-Zip (file archiver)'
    Winget   = '7zip.7zip'
  }
  'notepad-plus-plus'  = @{
    Describe = 'Notepad++ (source-code editor)'
    Winget   = 'Notepad++.Notepad++'
  }
  'winscp'             = @{
    Describe = 'WinSCP (SFTP/SCP/FTP client)'
    Winget   = 'WinSCP.WinSCP'
  }
  'cygwin'             = @{
    Describe  = 'Cygwin (POSIX environment, base install at C:\cygwin64; add packages with its setup)'
    Winget    = 'Cygwin.Cygwin'
    # Cygwin registers no uninstaller of its own: removal is deleting its root.
    Uninstall = {
      $root = 'C:\cygwin64'
      if ($script:DevSetupPurgeData) {
        Remove-Dir $root
        Remove-Dir (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Cygwin')
        Write-Log "Purged $root (including /home)."
      } else {
        Write-Log "Kept: $root — Cygwin has no uninstaller and its /home lives there; -PurgeData deletes it."
      }
    }
  }
  'libreoffice'        = @{
    Describe = 'LibreOffice (office suite)'
    Winget   = 'TheDocumentFoundation.LibreOffice'
  }
  'vmware-workstation' = @{
    Describe  = 'VMware Workstation 17 Pro (Broadcom installer you download; unattended install)'
    Install   = { Install-VMwareWorkstation }
    Uninstall = {
      $apps = Get-InstalledApp 'VMware Workstation*'
      if (-not $apps) { Write-Log 'VMware Workstation is not installed.'; return }
      foreach ($app in $apps) {
        if ($app.PSChildName -match '^\{[0-9A-Fa-f-]+\}$') {
          $p = Start-Process msiexec.exe -ArgumentList "/x $($app.PSChildName) /qn REBOOT=ReallySuppress" -Wait -PassThru
          if ($p.ExitCode -notin 0, 3010) { throw "VMware Workstation uninstall failed (exit $($p.ExitCode))." }
        }
      }
      Write-Log 'Virtual machines (Documents\Virtual Machines) are never deleted — remove them by hand.'
    }
  }
  'amazon-workspaces'  = @{
    Describe = 'Amazon WorkSpaces client'
    Winget   = 'Amazon.WorkspacesClient'
  }
  'llama-cpp'          = @{
    Describe = 'llama.cpp (ggml-org release build via winget — Vulkan backend, runs on NVIDIA/AMD/Intel GPUs)'
    Winget   = 'ggml.llamacpp'
  }
  'koboldcpp'          = @{
    Describe  = 'KoboldCpp (single-file GGUF runner + web UI, newest release)'
    Install   = {
      $dir = Join-Path $env:LOCALAPPDATA 'Programs\koboldcpp'
      $asset = 'koboldcpp-nocuda.exe'
      if (Test-NvidiaGpu) { $asset = 'koboldcpp.exe' }
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      Save-Url -Url "https://github.com/LostRuins/koboldcpp/releases/latest/download/$asset" -OutFile (Join-Path $dir 'koboldcpp.exe.part')
      Move-Item -Force (Join-Path $dir 'koboldcpp.exe.part') (Join-Path $dir 'koboldcpp.exe')
      Add-UserPath $dir
      Write-Ok "KoboldCpp installed ($asset) — run: koboldcpp --model model.gguf --gpulayers 99"
    }
    Uninstall = {
      $dir = Join-Path $env:LOCALAPPDATA 'Programs\koboldcpp'
      Remove-UserPath $dir
      Remove-Dir $dir
    }
  }
}

# Components of the shared catalog with no native Windows install path,
# and why — selecting one warns and skips, mirroring setup.sh's
# unsupported-on-target handling.
$script:WindowsUnsupported = [ordered]@{
  'nvidia-driver' = 'NVIDIA publishes no winget or scriptable driver package — install the Game Ready/Studio driver with the NVIDIA App (https://www.nvidia.com/en-us/software/nvidia-app/) or Windows Update.'
  'ik-llama-cpp'  = 'no Windows releases (source build needs Visual Studio Build Tools + CUDA) — use WSL2 Ubuntu with scripts/setup.sh.'
  'ktransformers' = 'Linux-only wheels — use WSL2 Ubuntu with scripts/setup.sh.'
  'vllm'          = 'vLLM runs only on Linux — use WSL2 Ubuntu with scripts/setup.sh.'
}

# VMware Workstation: Broadcom serves the installer only behind a (free)
# support-portal login, so it cannot be fetched — use the one you saved.
# It runs elevated, so it is never picked up on its own (a file dropped
# into Downloads must not become admin code): the path must be given, and
# the installer must carry a valid VMware/Broadcom Authenticode signature.
function Install-VMwareWorkstation {
  $exe = $env:DEV_SETUP_VMWARE_INSTALLER
  if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
    throw ('No VMware Workstation Pro installer given (DEV_SETUP_VMWARE_INSTALLER). Broadcom requires a (free) ' +
      'support-portal login: sign in at https://support.broadcom.com, open My Downloads > VMware Workstation Pro > ' +
      '17.x for Windows, download the .exe, then set DEV_SETUP_VMWARE_INSTALLER to its path and re-run with --vmware-workstation.')
  }
  $sig = Get-AuthenticodeSignature -FilePath $exe
  if ($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate -or
    $sig.SignerCertificate.Subject -notmatch 'O="?(VMware|Broadcom)') {
    throw "$exe is not a validly signed VMware/Broadcom installer (signature: $($sig.Status)) — not running it."
  }
  Write-Ok "Installer signature valid: $($sig.SignerCertificate.Subject)"
  $name = [IO.Path]::GetFileNameWithoutExtension($exe)   # VMware-Workstation-Full-17.6.4-24832109
  $version = ($name -split '-')[3]
  $build = ($name -split '-')[4]
  if ($version -like '17.*') {
    Write-Warn 'Workstation 17.x reached end of service in Nov 2025 and receives no more security fixes (VMSA-2026-0007 is fixed only in 26H1u1+).'
  }
  $installed = @(Get-InstalledApp 'VMware Workstation*' | Where-Object { $_.PSObject.Properties['DisplayVersion'] })
  if ($installed | Where-Object { $_.DisplayVersion -eq $version -or ($build -and $_.DisplayVersion -like "*$build*") }) {
    Write-Ok "VMware Workstation $version already installed."
    return
  }
  Write-Log "Installing $exe (unattended)..."
  $p = Start-Process -FilePath $exe -Wait -PassThru -ArgumentList '/s /v"/qn EULAS_AGREED=1 AUTOSOFTWAREUPDATE=0 DATACOLLECTION=0 REBOOT=ReallySuppress"'
  if ($p.ExitCode -eq 3010) { Write-Warn 'VMware Workstation installed; reboot to finish.'; return }
  if ($p.ExitCode -ne 0) { throw "VMware Workstation installer failed (exit $($p.ExitCode))." }
  Write-Ok "VMware Workstation $version installed."
}

# Run one catalog entry's install or uninstall.
function Invoke-ComponentAction {
  param([string]$Name, [ValidateSet('Install', 'Uninstall')][string]$Action)
  $c = $script:Components[$Name]
  if ($c.ContainsKey($Action)) { & $c[$Action]; return }
  if ($Action -eq 'Install') { Install-WingetPackage -Id $c.Winget }
  else { Uninstall-WingetPackage -Id $c.Winget }
}
