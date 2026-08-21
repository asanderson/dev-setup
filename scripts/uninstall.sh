#!/usr/bin/env bash
# uninstall.sh — remove components this repo's installer set up.
#
# By default ALL components are candidates: interactive runs confirm each
# one (default yes); non-interactive runs (DEV_SETUP_ASSUME_YES=1) remove
# exactly the selection from the command line, or everything when no
# selection flags are given.
#   Usage:              ./scripts/uninstall.sh [--modules LIST] [--<component> ...]
#   Unattended (all):   DEV_SETUP_ASSUME_YES=1 ./scripts/uninstall.sh
#   Unattended (some):  DEV_SETUP_ASSUME_YES=1 ./scripts/uninstall.sh --docker --opensearch
#
# User data (container volumes/images, ~/.m2, ~/go, ~/.kube, VS Code
# settings, Ollama models, Claude config, ...) is KEPT unless --purge-data
# is passed; every module says what it kept. Components uninstall in
# reverse dependency order (stacks before Docker, Maven before JDK).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export REPO_ROOT
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../config/versions.env
source "${REPO_ROOT}/config/versions.env"

# Same canonical order as setup.sh (kept in sync — the guard below catches
# drift); uninstalls run in REVERSE of it.
MODULES=(git claude-code claude-plugins vscode docker podman jdk maven cpp golang rust python cloud
         proton-vpn proton-mail proton-bridge proton-drive proton-pass proton-meet proton-authenticator
         elastic opensearch ollama)

for m in "${MODULES[@]}"; do
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/modules/${m}.sh"
done
for f in "${SCRIPT_DIR}"/modules/*.sh; do
  m="$(basename "$f" .sh)"
  [[ " ${MODULES[*]} " == *" $m "* ]] \
    || { err "BUG: module file '$m.sh' missing from uninstall.sh's MODULES list."; exit 1; }
done

usage() {
  echo "Usage: $0 [--modules LIST] [--<component> ...] [--purge-data] [--list]"
  echo "  Default: ALL components are candidates. Interactive runs confirm each"
  echo "  (default yes); non-interactive runs (DEV_SETUP_ASSUME_YES=1) remove"
  echo "  exactly the selection, or everything with no selection flags."
  echo "  --modules LIST   comma-separated components"
  echo "  --purge-data     also remove user data (volumes, models, configs, caches)"
  echo "  --list           print the available components and exit"
  echo "  Component flags: $(printf -- '--%s ' "${MODULES[@]}")"
}

PURGE_DATA=0
export PURGE_DATA
REQUESTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --modules)
      IFS=, read -ra _mods <<<"${2:?--modules needs a comma-separated list}"
      REQUESTED+=("${_mods[@]}")
      shift ;;
    --purge-data) PURGE_DATA=1 ;;
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
  require_sudo

  section "Component removal"
  if [[ "$PURGE_DATA" == "1" ]]; then
    warn "--purge-data: user data (volumes, models, configs, caches) will be removed too."
  else
    log "User data is kept (pass --purge-data to remove it as well)."
  fi

  # Candidates in REVERSE dependency order.
  local -a candidates=() selected=()
  local fn_name m i
  for (( i=${#MODULES[@]}-1; i>=0; i-- )); do
    m="${MODULES[$i]}"
    if [[ "${#REQUESTED[@]}" -gt 0 ]]; then
      [[ " ${REQUESTED[*]} " == *" $m "* ]] || continue
    fi
    candidates+=("$m")
  done
  [[ "${#REQUESTED[@]}" -gt 0 ]] && log "Selected on the command line: ${candidates[*]}"

  for m in "${candidates[@]}"; do
    fn_name="module_${m//-/_}_describe"
    if confirm "Uninstall $("$fn_name")?" y; then
      selected+=("$m")
    fi
  done

  if [[ "${#selected[@]}" -eq 0 ]]; then
    warn "Nothing selected — exiting."
    exit 0
  fi

  section "Uninstalling: ${selected[*]}"
  local -a failed=()
  local rc
  for m in "${selected[@]}"; do
    fn_name="module_${m//-/_}_uninstall"
    set +e
    ( set -e; "$fn_name" )
    rc=$?
    set -e
    if (( rc != 0 )); then
      failed+=("$m")
      err "Uninstall of '$m' failed (exit $rc); continuing with the rest."
    fi
  done

  # Leftover package-manager state from removed repos.
  if command_exists apt-get; then
    sudo apt-get autoremove -y >/dev/null 2>&1 || true
  else
    sudo dnf autoremove -y >/dev/null 2>&1 || true
  fi

  section "Summary"
  for m in "${selected[@]}"; do
    if [[ " ${failed[*]-} " == *" $m "* ]]; then
      err "$m: FAILED (re-run: ./scripts/uninstall.sh --$m)"
    else
      ok "$m: uninstalled"
    fi
  done
  [[ "${#failed[@]}" -gt 0 ]] && exit 1

  log "Done. Open a new shell so removed PATH entries disappear."
}

main "$@"
