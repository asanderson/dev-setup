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

# os_family — "deb" or "rpm", from the target OS (falling back to what the
# machine has). Modules use it to pick per-family installers and packages.
os_family() {
  case "${TARGET_OS:-}" in
    ubuntu|debian|pureos) echo deb; return ;;
    rocky|rhel)           echo rpm; return ;;
  esac
  if command_exists apt-get; then echo deb; else echo rpm; fi
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

# Remove only the packages that are actually installed. apt aborts the
# WHOLE transaction when any name is unknown to its configured archives
# (e.g. a vendor package whose repo is not present on this machine), so
# never pass raw lists to apt-get remove — filter here first. Family
# resolved by what the machine has; unknown/absent names are skipped.
pkg_remove() {
  local -a present=()
  local p
  if command_exists dpkg; then
    for p in "$@"; do
      dpkg -s "$p" >/dev/null 2>&1 && present+=("$p")
    done
    if [[ ${#present[@]} -gt 0 ]]; then
      sudo apt-get remove -y "${present[@]}"
    fi
  else
    for p in "$@"; do
      rpm -q "$p" >/dev/null 2>&1 && present+=("$p")
    done
    if [[ ${#present[@]} -gt 0 ]]; then
      sudo dnf remove -y "${present[@]}"
    fi
  fi
  return 0
}

# Same for vendor .rpm packages on Enterprise Linux targets.
fetch_rpm_install() {
  local url="$1" tmp
  tmp="$(mktemp -d)"
  fetch "$url" -o "${tmp}/pkg.rpm"
  sudo dnf install -y "${tmp}/pkg.rpm"
  rm -rf "$tmp"
}

# Family-dispatching vendor-package install: .deb URL on the Debian family,
# .rpm URL on Enterprise Linux.
fetch_pkg_install() {
  local deb_url="$1" rpm_url="$2"
  if [[ "$(os_family)" == deb ]]; then
    fetch_deb_install "$deb_url"
  else
    fetch_rpm_install "$rpm_url"
  fi
}

# ---------------------------------------------------------------------------
# GPU, local-LLM and per-user tool helpers
# ---------------------------------------------------------------------------
# has_nvidia_gpu — true when the PCI bus carries an NVIDIA display
# controller (vendor 0x10de, class 0x03xxxx), driver loaded or not; falls
# back to a working nvidia-smi (VMs and stubbed tests expose no sysfs).
has_nvidia_gpu() {
  local dev
  for dev in /sys/bus/pci/devices/*; do
    [[ "$(cat "${dev}/vendor" 2>/dev/null)" == 0x10de ]] || continue
    [[ "$(cat "${dev}/class" 2>/dev/null)" == 0x03* ]] && return 0
  done
  command_exists nvidia-smi && nvidia-smi >/dev/null 2>&1
}

# add_cuda_repo — NVIDIA's CUDA network repository for the target OS. It
# serves the CUDA Toolkit and NVIDIA's own driver packages; a release
# directory that does not exist yet (a brand-new distro version) falls
# back to the newest one NVIDIA publishes for that family.
add_cuda_repo() {
  local base="https://developer.download.nvidia.com/compute/cuda/repos" distro fallback
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${TARGET_OS:-ubuntu}" in
    ubuntu)     distro="ubuntu${VERSION_ID//./}"; fallback="ubuntu2404" ;;
    debian)     distro="debian${VERSION_ID%%.*}"; fallback="debian12" ;;
    rocky|rhel) distro="rhel${VERSION_ID%%.*}";   fallback="rhel9" ;;
    *) err "NVIDIA publishes no CUDA repository for ${TARGET_OS}."; return 1 ;;
  esac
  if [[ "$(os_family)" == deb ]]; then
    if ! fetch --head "${base}/${distro}/x86_64/cuda-keyring_1.1-1_all.deb" >/dev/null 2>&1; then
      warn "NVIDIA's CUDA repo has no ${distro} release yet; using ${fallback}."
      distro="$fallback"
    fi
    dpkg -s cuda-keyring >/dev/null 2>&1 \
      || fetch_deb_install "${base}/${distro}/x86_64/cuda-keyring_1.1-1_all.deb"
    _APT_UPDATED=""
  else
    if ! fetch --head "${base}/${distro}/x86_64/cuda-${distro}.repo" >/dev/null 2>&1; then
      warn "NVIDIA's CUDA repo has no ${distro} release yet; using ${fallback}."
      distro="$fallback"
    fi
    if [[ ! -s "/etc/yum.repos.d/cuda-${distro}.repo" ]]; then
      # Download first: a failed fetch must not leave an empty repo file
      # that every later run would take as already configured.
      local tmp; tmp="$(mktemp)"
      fetch "${base}/${distro}/x86_64/cuda-${distro}.repo" -o "$tmp" || { rm -f "$tmp"; return 1; }
      sudo install -m 0644 "$tmp" "/etc/yum.repos.d/cuda-${distro}.repo"
      rm -f "$tmp"
    fi
  fi
}

# github_latest_tag <owner/repo> [asset] — newest release tag, read from
# GitHub's releases/latest redirect (no API token, no rate limit); with an
# asset name, the releases/latest/download/<asset> redirect is the
# fallback (it names the tag too, and works where release pages are
# filtered). Empty on failure.
github_latest_tag() {
  local tag
  tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" 2>/dev/null \
    | sed -n 's|.*/releases/tag/||p' || true)"
  if [[ -z "$tag" && -n "${2:-}" ]]; then
    tag="$(curl -fsSI -o /dev/null -w '%{redirect_url}' "https://github.com/$1/releases/latest/download/$2" 2>/dev/null \
      | sed -n 's|.*/releases/download/\([^/]*\)/.*|\1|p' || true)"
  fi
  echo "$tag"
}

# ensure_local_bin_path — per-user tools land in ~/.local/bin: put it on
# PATH for this run and for future shells.
ensure_local_bin_path() {
  export PATH="$HOME/.local/bin:$PATH"
  if ! grep -qs '\.local/bin' "$HOME/.bashrc"; then
    # shellcheck disable=SC2016
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    warn "Added ~/.local/bin to PATH in ~/.bashrc (takes effect in new shells)."
  fi
}

# require_nvm_node <module> — load the nodejs module's nvm-managed Node
# into this shell, or fail with the select-nodejs-too guidance.
require_nvm_node() {
  export NVM_DIR="$HOME/.nvm"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    err "Node.js is not installed — run with the nodejs module too: ./scripts/setup.sh --nodejs --$1"
    return 1
  fi
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm use --silent default >/dev/null 2>&1 || true
  command_exists npm || { err "nvm has no default Node — re-run the nodejs module."; return 1; }
}

# require_uv <module> — uv comes from the python module.
require_uv() {
  export PATH="$HOME/.local/bin:$PATH"
  command_exists uv \
    || { err "uv is not installed — run with the python module too: ./scripts/setup.sh --python --$1"; return 1; }
}

# build_ggml_project <name> <git-url> <ref> <prefix> [cmake args...] —
# shallow-clone <ref> (tag or branch) of a llama.cpp-family repository,
# build it with CMake and install its binaries into <prefix>/bin, as the
# invoking user. CUDA is enabled when the toolkit's nvcc is present (the
# cuda-toolkit module): compiled for the local GPU (GGML_NATIVE) when one
# is visible, else portable (GGML_NATIVE=OFF: the projects' default CUDA
# architecture list, Blackwell's 120a included, and generic CPU code).
# Statically linked, so the binaries carry no libllama/libggml lookups.
# Re-runs rebuild only when the ref's commit or the CUDA choice changed.
build_ggml_project() {
  local name="$1" url="$2" ref="$3" prefix="$4"; shift 4
  # OpenSSL backs llama.cpp's HTTPS model downloads; ik_llama.cpp still
  # uses libcurl for them.
  if [[ "$(os_family)" == deb ]]; then
    apt_install git build-essential cmake libssl-dev libcurl4-openssl-dev
  else
    sudo dnf install -y git gcc gcc-c++ make cmake openssl-devel libcurl-devel
  fi

  local -a cmake_args=(-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF "$@")
  local cuda=no nvcc=""
  if command_exists nvcc; then nvcc="$(command -v nvcc)"
  elif [[ -x /usr/local/cuda/bin/nvcc ]]; then nvcc=/usr/local/cuda/bin/nvcc; fi
  if [[ -n "$nvcc" ]]; then
    cmake_args+=(-DGGML_CUDA=ON "-DCMAKE_CUDA_COMPILER=${nvcc}")
    if nvidia-smi >/dev/null 2>&1; then
      cuda=native
    else
      cmake_args+=(-DGGML_NATIVE=OFF)
      cuda=portable
    fi
  else
    warn "${name}: no CUDA toolkit (nvcc) found — building the CPU backend. Select cuda-toolkit and re-run for GPU offload."
  fi

  local commit stamp
  commit="$(git ls-remote "$url" "$ref" 2>/dev/null | head -n1 | cut -f1 || true)"
  [[ -n "$commit" ]] || { err "${name}: cannot resolve '${ref}' at ${url}."; return 1; }
  stamp="${commit} cuda=${cuda}"
  if [[ -f "${prefix}/.dev-setup-build" && "$(cat "${prefix}/.dev-setup-build")" == "$stamp" ]]; then
    ok "${name}: already built at ${ref} (${commit:0:12}, cuda=${cuda})."
    return 0
  fi

  local src; src="$(mktemp -d)"
  log "${name}: building ${ref} (${commit:0:12}, cuda=${cuda}) — CUDA builds take a while..."
  git clone --quiet --depth 1 --branch "$ref" "$url" "${src}/src"
  # Full compiler output goes to a log; a failure shows its tail.
  if ! { cmake -S "${src}/src" -B "${src}/build" "${cmake_args[@]}" \
         && cmake --build "${src}/build" --config Release -j "$(nproc)"; } >"${src}/build.log" 2>&1; then
    tail -n 40 "${src}/build.log" >&2
    rm -rf "$src"
    err "${name}: build failed (last lines above)."
    return 1
  fi
  rm -rf "${prefix}"
  mkdir -p "${prefix}/bin"
  find "${src}/build/bin" -maxdepth 1 -type f -perm -u+x -exec cp {} "${prefix}/bin/" \;
  echo "$stamp" > "${prefix}/.dev-setup-build"
  rm -rf "$src"
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
