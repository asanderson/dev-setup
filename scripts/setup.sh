#!/usr/bin/env bash
# setup.sh — interactive development environment installer for Ubuntu.
#
# Prompts per tool; each module is idempotent and safe to re-run.
#   Usage:            ./scripts/setup.sh
#   Unattended (all): DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh
#
# NVIDIA driver and kernel setup are separate, reboot-heavy steps that live
# in the dual-boot repo: https://github.com/asanderson/dual-boot

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export REPO_ROOT

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../config/versions.env
source "${REPO_ROOT}/config/versions.env"

# Module order matters: docker before elastic, jdk before maven,
# nvidia-dependent modules (ollama) last.
MODULES=(git claude-code docker jdk maven cpp golang rust elastic ollama)

for m in "${MODULES[@]}"; do
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/modules/${m}.sh"
done

main() {
  require_not_root
  require_ubuntu "26.04"
  require_network
  require_sudo

  section "Ubuntu development environment setup"
  log "Machine: $(sed 's/^ *//' /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo unknown)"
  log "Kernel:  $(uname -r)"
  if command_exists nvidia-smi; then
    log "GPU:     $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo 'NVIDIA (driver loading)')"
  else
    warn "NVIDIA driver not active. Install it first for GPU support (see github.com/asanderson/dual-boot), then reboot."
  fi

  # Base tools every module relies on.
  apt_install curl ca-certificates gnupg lsb-release openssl

  # ---- interactive selection ------------------------------------------------
  section "Select components"
  local -a selected=()
  local fn_name m
  for m in "${MODULES[@]}"; do
    fn_name="module_${m//-/_}_describe"
    if confirm "Install $("$fn_name")?" y; then
      selected+=("$m")
    fi
  done

  if [[ "${#selected[@]}" -eq 0 ]]; then
    warn "Nothing selected — exiting."
    exit 0
  fi

  section "Installing: ${selected[*]}"
  local -a failed=()
  local rc
  for m in "${selected[@]}"; do
    fn_name="module_${m//-/_}_install"
    # Run each module in a subshell with errexit re-armed: a plain
    # `if ! "$fn_name"` would suppress `set -e` inside the module (bash
    # ignores errexit in condition contexts), letting failures go unnoticed.
    set +e
    ( set -e; "$fn_name" )
    rc=$?
    set -e
    if (( rc != 0 )); then
      failed+=("$m")
      err "Module '$m' failed (exit $rc); continuing with the rest."
    fi
  done

  # ---- summary --------------------------------------------------------------
  section "Summary"
  for m in "${selected[@]}"; do
    if [[ " ${failed[*]-} " == *" $m "* ]]; then
      err "$m: FAILED (re-run: ./scripts/setup.sh and select only '$m')"
    else
      ok "$m: installed"
    fi
  done
  [[ "${#failed[@]}" -gt 0 ]] && exit 1

  log "Done. Open a new shell so PATH updates (Go, Maven, Rust, ~/.local/bin) take effect."
}

main "$@"
