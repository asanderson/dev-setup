# shellcheck shell=bash
# common.sh — shared helpers for dev-setup scripts.
# Source this file; do not execute it directly.

set -o pipefail

# ---------------------------------------------------------------------------
# Colors (disabled when stdout is not a TTY)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

log()  { printf '%s[dev-setup]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s[  ok  ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[ warn ]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[ fail ]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

section() {
  printf '\n%s%s==> %s%s\n' "$C_BOLD" "$C_BLUE" "$*" "$C_RESET"
}

# ---------------------------------------------------------------------------
# Prompting
# ---------------------------------------------------------------------------
# confirm "Question?" [default: y|n] -> returns 0 for yes, 1 for no.
# Honors DEV_SETUP_ASSUME_YES=1 for unattended runs.
confirm() {
  local prompt="$1" default="${2:-y}" reply hint
  if [[ "${DEV_SETUP_ASSUME_YES:-0}" == "1" ]]; then
    log "$prompt -> yes (DEV_SETUP_ASSUME_YES=1)"
    return 0
  fi
  if [[ "$default" == "y" ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
  while true; do
    read -r -p "${C_BOLD}${prompt}${C_RESET} ${hint} " reply || reply=""
    reply="${reply,,}"
    [[ -z "$reply" ]] && reply="$default"
    case "$reply" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) warn "Please answer y or n." ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Environment checks
# ---------------------------------------------------------------------------
require_not_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    die "Run this script as your regular user, not root. It uses sudo where needed."
  fi
}

require_sudo() {
  if ! sudo -v; then
    die "sudo privileges are required."
  fi
  # Keep the sudo timestamp alive for the duration of the run.
  ( while true; do sudo -n true 2>/dev/null || exit; sleep 60; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap '[[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

require_ubuntu() {
  local want_release="${1:-}"
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release; is this Ubuntu?"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "$ID" == "ubuntu" ]] || die "This script targets Ubuntu (detected: ${ID:-unknown})."
  if [[ -n "$want_release" && "$VERSION_ID" != "$want_release" ]]; then
    warn "Expected Ubuntu ${want_release}, found ${VERSION_ID}. Continuing, but packages may differ."
  fi
}

# require_target_os <os> — the installer configures the system it runs on:
# verify /etc/os-release matches the declared target OS. The ubuntu target
# keeps the tested-version warning (26.04).
require_target_os() {
  local target="$1"
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release; unsupported system."
  # shellcheck disable=SC1091
  . /etc/os-release
  local detected="${ID:-unknown}"
  if [[ "$detected" != "$target" ]]; then
    die "Target OS is '${target}' but this machine is '${detected}' — the installer configures the system it runs on."
  fi
  if [[ "$target" == "ubuntu" && "${VERSION_ID:-}" != "26.04" ]]; then
    warn "Expected Ubuntu 26.04, found ${VERSION_ID:-unknown}. Continuing, but packages may differ."
  fi
}

require_network() {
  if ! timeout 10 bash -c ':</dev/tcp/archive.ubuntu.com/80' 2>/dev/null; then
    die "No network connectivity to archive.ubuntu.com. Connect to the internet and retry."
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Apt helpers
# ---------------------------------------------------------------------------
apt_update_once() {
  if [[ -z "${_APT_UPDATED:-}" ]]; then
    sudo apt-get update -y
    _APT_UPDATED=1
  fi
}

apt_install() {
  apt_update_once
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

# Install a keyring + apt source pair for a third-party repo.
# usage: add_apt_repo <name> <key_url> <repo_line>
add_apt_repo() {
  local name="$1" key_url="$2" repo_line="$3"
  local keyring="/etc/apt/keyrings/${name}.gpg"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "$key_url" | sudo gpg --dearmor --yes -o "$keyring"
  sudo chmod a+r "$keyring"
  echo "$repo_line" | sudo tee "/etc/apt/sources.list.d/${name}.list" >/dev/null
  _APT_UPDATED=""   # force refresh after adding a source
}

# Download a vendor .deb over HTTPS and install it (apt resolves its
# dependencies). Used by modules whose vendor publishes a stable
# latest-version .deb URL rather than an apt repository.
fetch_deb_install() {
  local url="$1" tmp
  tmp="$(mktemp -d)"
  fetch "$url" -o "${tmp}/pkg.deb"
  apt_install "${tmp}/pkg.deb"
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------
# Fetch a URL to stdout with retries.
fetch() {
  curl -fsSL --retry 4 --retry-delay 2 --retry-connrefused "$@"
}

# Compare installed vs candidate versions where useful.
installed_version() {
  # usage: installed_version <command> <version-flag...>
  local cmd="$1"; shift
  command_exists "$cmd" && "$cmd" "$@" 2>/dev/null | head -n1 || true
}
