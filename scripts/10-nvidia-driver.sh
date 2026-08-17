#!/usr/bin/env bash
# 10-nvidia-driver.sh — official NVIDIA driver for the RTX 5090 Laptop GPU.
#
# Blackwell (RTX 50-series) GPUs are supported ONLY by the open GPU kernel
# modules — install an "-open" driver package. The 580 branch is the
# long-lived production branch (pairs with CUDA 13.x); newer branches
# (e.g. 595) also support Blackwell.
#
# Run, reboot, then verify with: nvidia-smi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../config/versions.env
source "${REPO_ROOT}/config/versions.env"

main() {
  require_not_root
  require_ubuntu "26.04"
  require_network
  require_sudo

  section "NVIDIA driver (RTX 5090 Laptop GPU / Blackwell)"

  if ! lspci -nn 2>/dev/null | grep -qi 'nvidia'; then
    die "No NVIDIA GPU visible on PCI. If this is the Raider, check BIOS GPU/hybrid settings."
  fi

  # ---- Secure Boot ---------------------------------------------------------
  apt_install mokutil
  if mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
    warn "Secure Boot is ENABLED. Ubuntu will sign the NVIDIA modules with a"
    warn "Machine Owner Key (MOK). You will be asked to set a one-time password;"
    warn "on the next reboot a blue 'MOK management' screen appears:"
    warn "  Enroll MOK -> Continue -> Yes -> enter that password -> reboot."
    warn "If you skip enrollment the driver will NOT load."
    confirm "Understood — continue?" y || exit 1
  else
    log "Secure Boot is disabled; no MOK enrollment needed."
  fi

  # ---- Pick and install the driver ----------------------------------------
  apt_install ubuntu-drivers-common
  section "Detected driver options"
  ubuntu-drivers devices || true

  local recommended
  recommended="$(ubuntu-drivers devices 2>/dev/null | awk '/recommended/ {print $3; exit}')"

  local target=""
  if [[ -n "$recommended" ]]; then
    if [[ "$recommended" == *-open ]]; then
      target="$recommended"
    else
      # Blackwell requires the open kernel modules — prefer the -open variant
      # of the recommended branch when the recommendation isn't already open.
      if apt-cache show "${recommended}-open" >/dev/null 2>&1; then
        target="${recommended}-open"
      else
        target="$recommended"
        warn "No '-open' variant of ${recommended} found; using it as-is."
      fi
    fi
  else
    target="nvidia-driver-${NVIDIA_DRIVER_BRANCH}-open"
    warn "ubuntu-drivers made no recommendation; falling back to ${target}."
  fi

  log "Installing: ${target}"
  confirm "Proceed with ${target}?" y || die "Aborted."
  apt_install "${target}"

  # nvidia-smi & friends come with the driver metapackage; CUDA toolkit is optional.
  if confirm "Also install the CUDA toolkit (nvcc, ~3GB — for compiling GPU code)?" n; then
    apt_install nvidia-cuda-toolkit || warn "CUDA toolkit install failed; you can use NVIDIA's cuda repo instead."
  fi

  section "Done — reboot required"
  ok "Driver installed: ${target}"
  log "1. sudo reboot"
  log "2. If prompted, complete MOK enrollment (see above)."
  log "3. Verify: nvidia-smi   (should list 'GeForce RTX 5090 Laptop GPU')"
  log "4. Hybrid graphics: 'prime-select query' shows the mode; 'on-demand' (default)"
  log "   renders on Intel and offloads to NVIDIA per-app; 'sudo prime-select nvidia'"
  log "   forces the dGPU (better for external displays wired to the dGPU)."
}

main "$@"
