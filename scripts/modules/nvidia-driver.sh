# shellcheck shell=bash
# Module: NVIDIA GPU driver, per target OS — the open kernel modules on
# NVIDIA's channel (the only flavor that drives Blackwell/RTX 50 GPUs, and
# the only one NVIDIA ships from R615 on):
#   ubuntu       Canonical's `ubuntu-drivers install` — the archive's
#                recommended package for the detected GPU (the -open branch
#                on Blackwell), signed modules for Secure Boot
#   debian       NVIDIA's CUDA repo `nvidia-open` (Debian's own packages stop
#                at 550, which predates Blackwell)
#   rocky/rhel   NVIDIA's CUDA repo, open-dkms module stream + `nvidia-open`
#                (EPEL for DKMS, CRB for its build deps)
# PureOS gets no NVIDIA channel at all. Machines without an NVIDIA GPU are
# skipped cleanly. A reboot is required before the driver loads; for the
# MSI Raider dual-boot laptop the full runbook (kernel, Secure Boot MOK)
# stays in https://github.com/asanderson/dual-boot.
# https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/

module_nvidia_driver_describe() { echo "NVIDIA GPU driver (open kernel modules; ubuntu-drivers or NVIDIA's repo)"; }

module_nvidia_driver_install() {
  section "NVIDIA GPU driver"
  if ! has_nvidia_gpu; then
    log "No NVIDIA GPU detected on this machine — nothing to install (skipped)."
    return 0
  fi
  if nvidia-smi >/dev/null 2>&1; then
    log "Driver already active: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -n1). Updating packages in place."
  fi
  case "${TARGET_OS:-ubuntu}" in
    ubuntu)
      apt_install ubuntu-drivers-common "linux-headers-$(uname -r)"
      # Noninteractive: DKMS/Secure Boot debconf prompts must not block
      # an unattended run (sudo's env_reset would drop an exported value).
      sudo DEBIAN_FRONTEND=noninteractive ubuntu-drivers install
      ;;
    debian)
      _nvidia_debian_contrib
      apt_install "linux-headers-$(uname -r)"
      add_cuda_repo
      apt_install nvidia-open
      ;;
    rocky|rhel)
      sudo dnf install -y "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)" \
        || sudo dnf install -y kernel-devel kernel-headers
      if [[ "$TARGET_OS" == rhel ]]; then
        sudo subscription-manager repos --enable "codeready-builder-for-rhel-9-$(uname -m)-rpms" \
          || warn "Could not enable CodeReady Builder (needs an entitled RHEL host)."
        sudo dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm" 2>/dev/null || true
      else
        sudo dnf config-manager --set-enabled crb
        sudo dnf install -y epel-release
      fi
      add_cuda_repo
      sudo dnf module enable -y nvidia-driver:open-dkms 2>/dev/null || true
      sudo dnf install -y nvidia-open
      ;;
    *)
      err "NVIDIA publishes no driver channel for ${TARGET_OS}."
      return 1
      ;;
  esac
  ok "NVIDIA driver packages installed."
  warn "Reboot to load the driver, then check with: nvidia-smi"
  if mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    warn "Secure Boot is on: if the driver does not load after the reboot, enroll the DKMS signing key"
    warn "(sudo mokutil --import /var/lib/dkms/mok.pub, then confirm at the blue MOK screen on boot)."
  fi
  log "Re-run docker/ollama afterwards if they were installed before the driver (GPU branches key off it)."
}

# NVIDIA's Debian instructions need the contrib component enabled.
_nvidia_debian_contrib() {
  if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
    if ! grep -q '^Components:.*contrib' /etc/apt/sources.list.d/debian.sources; then
      sudo sed -i '/^Components:/ s/$/ contrib/' /etc/apt/sources.list.d/debian.sources
      _APT_UPDATED=""
    fi
  elif [[ -f /etc/apt/sources.list ]] && ! grep -Eq '^deb .* contrib' /etc/apt/sources.list; then
    sudo sed -i -E '/^deb .* main/ s/$/ contrib/' /etc/apt/sources.list
    _APT_UPDATED=""
  fi
}

module_nvidia_driver_uninstall() {
  section "Uninstall: NVIDIA GPU driver"
  local -a pkgs
  if command_exists dpkg; then
    mapfile -t pkgs < <(dpkg-query -W -f='${Package}\n' 'nvidia-*' 'libnvidia-*' 'xserver-xorg-video-nvidia*' 2>/dev/null \
      | grep -Ev '^(lib)?nvidia-container' || true)
  else
    mapfile -t pkgs < <(rpm -qa --qf '%{NAME}\n' 'nvidia-*' 'kmod-nvidia*' 'libnvidia-*' 2>/dev/null \
      | grep -Ev '^(lib)?nvidia-container' || true)
  fi
  # (the NVIDIA Container Toolkit and its libnvidia-container libraries
  # belong to the docker module.)
  if [[ ${#pkgs[@]} -eq 0 ]]; then
    log "No NVIDIA driver packages installed."
    return 0
  fi
  warn "Removing the NVIDIA driver: the desktop falls back to nouveau/llvmpipe after a reboot."
  pkg_remove "${pkgs[@]}"
  if ! dpkg -s cuda-toolkit >/dev/null 2>&1 && ! rpm -q cuda-toolkit >/dev/null 2>&1; then
    pkg_remove cuda-keyring
    sudo rm -f /etc/yum.repos.d/cuda-rhel*.repo
  fi
  warn "Reboot to unload the old driver."
}
