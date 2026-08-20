#!/usr/bin/env bash
# setup.sh — interactive development environment installer for Ubuntu.
#
# Prompts per tool; each module is idempotent and safe to re-run.
#   Usage:              ./scripts/setup.sh [--modules LIST] [--<component> ...]
#   Unattended (all):   DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh
#   Unattended (some):  DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh --docker --opensearch
#
# Component selection: every component has a matching command-line flag
# (--git, --docker, --opensearch, ...) and --modules takes a comma-separated
# list. Interactive runs still confirm each component (selection flags just
# pre-scope the menu); non-interactive runs install exactly the selected
# components — or everything when no selection flags are given.
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

# Module order matters: docker before elastic/opensearch, jdk before maven,
# nvidia-dependent modules (ollama) last.
MODULES=(git claude-code vscode docker jdk maven cpp golang rust python elastic opensearch ollama)

for m in "${MODULES[@]}"; do
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/modules/${m}.sh"
done

usage() {
  echo "Usage: $0 [--modules LIST] [--<component> ...] [--list]"
  echo "  Interactive runs confirm each component (default yes); selection flags"
  echo "  pre-scope which components are offered. Non-interactive runs"
  echo "  (DEV_SETUP_ASSUME_YES=1) install exactly the selected components, or"
  echo "  everything when no selection flags are given."
  echo "  --modules LIST   comma-separated components"
  echo "  --list           print the available components and exit"
  echo "  Component flags: $(printf -- '--%s ' "${MODULES[@]}")"
}

REQUESTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --modules)
      IFS=, read -ra _mods <<<"${2:?--modules needs a comma-separated list}"
      REQUESTED+=("${_mods[@]}")
      shift ;;
    --list) printf '%s\n' "${MODULES[@]}"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --*)
      _m="${1#--}"
      if [[ " ${MODULES[*]} " == *" ${_m} "* ]]; then
        REQUESTED+=("$_m")
      else
        err "Unknown argument: $1"; usage; exit 2
      fi ;;
    *) err "Unknown argument: $1"; usage; exit 2 ;;
  esac
  shift
done
for _m in ${REQUESTED[@]+"${REQUESTED[@]}"}; do
  [[ " ${MODULES[*]} " == *" ${_m} "* ]] \
    || { err "Unknown component: ${_m} (see --list)"; usage; exit 2; }
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

  # ---- component selection --------------------------------------------------
  # Command-line selection pre-scopes the menu, in canonical MODULES order so
  # ordering constraints (docker before elastic/opensearch) always hold.
  section "Select components"
  local -a candidates=() selected=()
  local fn_name m
  if [[ "${#REQUESTED[@]}" -gt 0 ]]; then
    for m in "${MODULES[@]}"; do
      [[ " ${REQUESTED[*]} " == *" $m "* ]] && candidates+=("$m")
    done
    log "Selected on the command line: ${candidates[*]}"
  else
    candidates=("${MODULES[@]}")
  fi
  for m in "${candidates[@]}"; do
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
