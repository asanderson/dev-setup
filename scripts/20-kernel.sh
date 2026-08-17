#!/usr/bin/env bash
# 20-kernel.sh — verify the kernel meets the 7.0+ requirement (and optionally
# move to a newer mainline kernel).
#
# Ubuntu 26.04 LTS ships Linux 7.0 as its GA kernel (7.0 is the upstream
# release that followed 6.19), so a stock install already satisfies
# "kernel 7.0 or newer" — this script mostly just confirms that.
#
# Newer kernels arrive through:
#   * linux-generic-hwe-26.04 — Canonical's HWE stack (currently also 7.0;
#     rolls forward at later point releases) and stays signed/supported.
#     Preferred.
#   * kernel.ubuntu.com mainline builds — bleeding edge (7.1+/7.2-rc), but
#     UNSIGNED (Secure Boot must be off or modules self-signed), unsupported,
#     with no security updates — and NVIDIA DKMS modules are not expected to
#     build against them. Only for troubleshooting very new hardware.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REQUIRED_MAJOR=7

main() {
  require_not_root
  require_ubuntu "26.04"

  section "Kernel check"
  local running major
  running="$(uname -r)"
  major="${running%%.*}"
  log "Running kernel: ${running}"

  if (( major >= REQUIRED_MAJOR )); then
    ok "Kernel ${running} satisfies the ${REQUIRED_MAJOR}.0+ requirement."
  else
    warn "Kernel ${running} is older than ${REQUIRED_MAJOR}.0."
    warn "On Ubuntu 26.04 that usually means you're booted into an old entry —"
    warn "run 'sudo apt full-upgrade', reboot, and pick the newest kernel in GRUB."
  fi

  require_sudo
  require_network

  if confirm "Enable the HWE kernel stack (linux-generic-hwe-26.04) to track newer signed kernels?" y; then
    apt_install "linux-generic-hwe-26.04" || warn "HWE metapackage not available yet (it appears around 26.04.2)."
  fi

  if confirm "Install the 'mainline' tool for bleeding-edge kernel.ubuntu.com builds (unsigned — Secure Boot caveats)?" n; then
    apt_install software-properties-common
    sudo add-apt-repository -y ppa:cappelikan/ppa
    _APT_UPDATED=""
    apt_install mainline
    warn "Mainline kernels are unsigned: with Secure Boot enabled they won't boot"
    warn "unless you disable Secure Boot or sign them yourself. NVIDIA DKMS may"
    warn "also fail to build against a kernel newer than the driver supports."
    log "Usage: 'mainline --list' then 'sudo mainline --install-latest'."
  fi

  section "Current kernel status"
  ok "$(uname -sr) on $(. /etc/os-release && echo "$PRETTY_NAME")"
}

main "$@"
