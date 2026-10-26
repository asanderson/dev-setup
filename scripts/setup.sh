#!/usr/bin/env bash
# setup.sh — interactive development environment installer for Ubuntu.
#
# Prompts per tool; each module is idempotent and safe to re-run.
#   Usage:              ./scripts/setup.sh [--os OS] [--modules LIST] [--<component> ...]
#   Unattended (all):   DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh
#   Unattended (some):  DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh --docker --opensearch
#
# Target OS: interactive runs prompt for it (default ubuntu, the tested
# platform); non-interactive runs take --os (default ubuntu). Components not
# supported on the target OS are warned about — skipped unattended,
# confirmable (default no) interactively — and the installer verifies it is
# actually running on the declared target before touching anything.
#
# Component selection: every component has a matching command-line flag
# (--git, --docker, --opensearch, ...) and --modules takes a comma-separated
# list. Interactive runs still confirm each component (selection flags just
# pre-scope the menu); non-interactive runs install exactly the selected
# components — or everything when no selection flags are given.
#
# The nvidia-driver module installs the GPU driver per distro (reboot
# afterwards); the MSI Raider dual-boot laptop's full OS runbook (kernel,
# Secure Boot) lives in https://github.com/asanderson/dual-boot. Native
# Windows components come from scripts/setup.ps1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export REPO_ROOT

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../config/versions.env
source "${REPO_ROOT}/config/versions.env"

# Module order matters: the NVIDIA driver and CUDA Toolkit first (docker's
# container toolkit, ollama and the llama.cpp builds key off them),
# claude-code before claude-plugins, nodejs/python before the agent CLIs
# that run on Node, Bun or uv, docker before elastic/opensearch, jdk before
# maven, and the local-LLM runtimes (ollama, then ollama-models which pulls
# into it, then the llama.cpp family and the Python serving stacks) last.
MODULES=(nvidia-driver cuda-toolkit
         git nodejs claude-code claude-plugins vscode docker podman jdk maven cpp golang rust python cloud
         codex opencode oh-my-pi hermes-agent openclaw strata
         7zip libreoffice vmware-workstation amazon-workspaces
         proton-vpn proton-mail proton-bridge proton-drive proton-pass proton-meet proton-authenticator
         elastic opensearch ollama ollama-models llama-cpp ik-llama-cpp koboldcpp ktransformers vllm)

# Target operating systems. The installer configures the machine it runs on;
# the target names the intent so component support is checked up front.
# qubes is in the catalog to give honest guidance (template VM) instead of
# "unknown argument"; windows points at the native Windows installer
# (scripts/setup.ps1, winget-based) and WSL2 for the Linux toolchain.
OS_CATALOG=(ubuntu debian pureos rocky rhel qubes windows)
TARGET_OS=""

# Per-component OS support, exactly as the modules are written. Most
# modules now dispatch per family (apt vs dnf, .deb vs .rpm, vendor apt vs
# yum repos) and cover every target. The remaining gaps are vendor
# channels that genuinely do not exist: Docker publishes no PureOS suite
# (podman covers containers there), and Proton VPN's official Linux app
# has no Enterprise Linux channel (the other Proton apps ship .rpms).
# NVIDIA publishes no driver/CUDA channel for PureOS (a free-software-only
# distro), so the GPU-bound stack skips it; Amazon WorkSpaces ships an
# Ubuntu client only. Windows-only components (Git Bash, Notepad++,
# WinSCP, Cygwin) live in scripts/setup.ps1.
# See docs/dev-tools.md#target-operating-systems.
declare -A MODULE_SUPPORT=(
  [nvidia-driver]="ubuntu debian rocky rhel"
  [cuda-toolkit]="ubuntu debian rocky rhel"
  [git]="ubuntu debian pureos rocky rhel"
  [nodejs]="ubuntu debian pureos rocky rhel"
  [claude-code]="ubuntu debian pureos rocky rhel"
  [claude-plugins]="ubuntu debian pureos rocky rhel"
  [vscode]="ubuntu debian pureos rocky rhel"
  [docker]="ubuntu debian rocky rhel"
  [podman]="ubuntu debian pureos rocky rhel"
  [jdk]="ubuntu debian pureos rocky rhel"
  [maven]="ubuntu debian pureos rocky rhel"
  [cpp]="ubuntu debian pureos rocky rhel"
  [golang]="ubuntu debian pureos rocky rhel"
  [rust]="ubuntu debian pureos rocky rhel"
  [python]="ubuntu debian pureos rocky rhel"
  [cloud]="ubuntu debian pureos rocky rhel"
  [codex]="ubuntu debian pureos rocky rhel"
  [opencode]="ubuntu debian pureos rocky rhel"
  [oh-my-pi]="ubuntu debian pureos rocky rhel"
  [hermes-agent]="ubuntu debian pureos rocky rhel"
  [openclaw]="ubuntu debian pureos rocky rhel"
  [strata]="ubuntu debian pureos rocky rhel"
  [7zip]="ubuntu debian pureos rocky rhel"
  [libreoffice]="ubuntu debian pureos rocky rhel"
  [vmware-workstation]="ubuntu debian pureos rocky rhel"
  [amazon-workspaces]="ubuntu"
  [proton-vpn]="ubuntu debian pureos"
  [proton-mail]="ubuntu debian pureos rocky rhel"
  [proton-bridge]="ubuntu debian pureos rocky rhel"
  [proton-drive]="ubuntu debian pureos rocky rhel"
  [proton-pass]="ubuntu debian pureos rocky rhel"
  [proton-meet]="ubuntu debian pureos rocky rhel"
  # authenticator's package needs libwebkit2gtk-4.1, which EL9 repos do
  # not provide (verified against Rocky 9's full repo set).
  [proton-authenticator]="ubuntu debian pureos"
  [elastic]="ubuntu debian pureos rocky rhel"
  [opensearch]="ubuntu debian pureos rocky rhel"
  [ollama]="ubuntu debian pureos rocky rhel"
  [ollama-models]="ubuntu debian pureos rocky rhel"
  [llama-cpp]="ubuntu debian pureos rocky rhel"
  [ik-llama-cpp]="ubuntu debian pureos rocky rhel"
  [koboldcpp]="ubuntu debian pureos rocky rhel"
  # CUDA-only serving stacks: no NVIDIA driver channel on PureOS, and
  # KTransformers' wheels need glibc 2.35+ (EL9 ships 2.34).
  [ktransformers]="ubuntu debian"
  [vllm]="ubuntu debian rocky rhel"
)

for m in "${MODULES[@]}"; do
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/modules/${m}.sh"
done

usage() {
  echo "Usage: $0 [--os OS] [--modules LIST] [--<component> ...] [--list]"
  echo "  Interactive runs confirm each component (default yes); selection flags"
  echo "  pre-scope which components are offered. Non-interactive runs"
  echo "  (DEV_SETUP_ASSUME_YES=1) install exactly the selected components, or"
  echo "  everything when no selection flags are given."
  echo "  --os OS          target operating system (default: ubuntu;"
  echo "                   catalog: ${OS_CATALOG[*]}). Components not supported"
  echo "                   on the target are warned about and skipped unattended."
  echo "  --modules LIST   comma-separated components"
  echo "  --list           print the available components and exit"
  echo "  Component flags: $(printf -- '--%s ' "${MODULES[@]}")"
}

REQUESTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --os)
      TARGET_OS="${2:?--os needs an operating system}"
      if [[ " ${OS_CATALOG[*]} " != *" ${TARGET_OS} "* ]]; then
        err "Unknown target OS: ${TARGET_OS} (catalog: ${OS_CATALOG[*]})"; usage; exit 2
      fi
      shift ;;
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

  section "Development environment setup"
  log "Machine: $(sed 's/^ *//' /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo unknown)"
  log "Kernel:  $(uname -r)"
  if command_exists nvidia-smi; then
    log "GPU:     $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo 'NVIDIA (driver loading)')"
  else
    warn "NVIDIA driver not active. Install it first for GPU support (the nvidia-driver module, or github.com/asanderson/dual-boot), then reboot."
  fi

  # ---- target operating system ----------------------------------------------
  section "Target operating system"
  if [[ -z "$TARGET_OS" ]]; then
    if [[ "${DEV_SETUP_ASSUME_YES:-0}" == "1" ]]; then
      TARGET_OS="ubuntu"
      log "No --os given — defaulting to ubuntu."
    else
      local t
      while true; do
        read -r -p "${C_BOLD}Target operating system${C_RESET} [${OS_CATALOG[*]}] (ubuntu): " t || t=""
        TARGET_OS="${t:-ubuntu}"
        [[ " ${OS_CATALOG[*]} " == *" ${TARGET_OS} "* ]] && break
        warn "Unknown OS '${TARGET_OS}' — pick one of: ${OS_CATALOG[*]}"
      done
    fi
  fi
  log "Target OS: ${TARGET_OS}"
  case "$TARGET_OS" in
    qubes)
      die "Qubes OS: dev tools belong in a template VM, not dom0 — run this inside a Debian-template qube with --os debian." ;;
    windows)
      die "Windows: run the native Windows installer from PowerShell instead — scripts\\setup.ps1 (winget-based: Git Bash, 7-Zip, Notepad++, WinSCP, Cygwin, ...; see docs/dev-tools.md#windows). For this Linux toolchain use WSL2 with Ubuntu and --os ubuntu." ;;
  esac

  # ---- component selection --------------------------------------------------
  # Command-line selection pre-scopes the menu, in canonical MODULES order so
  # ordering constraints (docker before elastic/opensearch) always hold.
  # Components without support for the target OS are warned about: unattended
  # runs never install them; interactive runs may force one (default no).
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
    [[ -n "${MODULE_SUPPORT[$m]:-}" ]] || die "BUG: module '$m' has no MODULE_SUPPORT entry."
    fn_name="module_${m//-/_}_describe"
    if [[ " ${MODULE_SUPPORT[$m]} " != *" ${TARGET_OS} "* ]]; then
      warn "${m}: not supported on ${TARGET_OS} as written (supported: ${MODULE_SUPPORT[$m]})."
      if [[ "${DEV_SETUP_ASSUME_YES:-0}" == "1" ]]; then
        warn "${m}: skipping — unattended runs never install unsupported components."
        continue
      fi
      if confirm "Select ${m} anyway (its installer will likely fail here)?" n; then
        selected+=("$m")
      fi
      continue
    fi
    if confirm "Install $("$fn_name")?" y; then
      selected+=("$m")
    fi
  done

  if [[ "${#selected[@]}" -eq 0 ]]; then
    warn "Nothing selected — exiting."
    exit 0
  fi

  # ---- machine checks (the installer acts on the system it runs on) ---------
  require_target_os "$TARGET_OS"
  require_network
  require_sudo

  # Base tools every module relies on.
  if command_exists apt-get; then
    apt_install curl ca-certificates gnupg lsb-release openssl
  else
    # --allowerasing: EL ships curl-minimal, which conflicts with full curl
    # until dnf is allowed to swap them.
    sudo dnf install -y --allowerasing curl ca-certificates gnupg2 openssl
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
