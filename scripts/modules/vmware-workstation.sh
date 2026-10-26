# shellcheck shell=bash
# Module: VMware Workstation Pro 26H1 — Broadcom's desktop hypervisor (free
# for commercial, educational and personal use). Broadcom serves the
# installer only behind a (free) Broadcom support-portal login, so there is
# no URL to fetch: download the Linux .bundle yourself, then point the
# module at it with DEV_SETUP_VMWARE_BUNDLE=/path/to/bundle. The bundle runs
# as root and carries no signature, so the module never picks one up on
# its own (a file dropped into ~/Downloads must not become root code), and
# DEV_SETUP_VMWARE_BUNDLE_SHA256 — the checksum Broadcom's portal lists for
# the download — is verified when given; without it the module prints the
# bundle's SHA-256 for you to compare. Releases older than
# VMWARE_WORKSTATION_MIN_RELEASE (26H1, versions.env) are refused: 26H1 is
# the first release supporting Ubuntu 26.04 hosts, 26H1u1 carries the
# VMSA-2026-0007 fix, and 17.x reached end of service in Nov 2025. Newer
# releases (26H2, ...) install too. The bundle
# is a distro-agnostic installer; the module adds the kernel-module build
# prerequisites, runs it unattended and builds vmmon/vmnet for the running
# kernel. Secure Boot machines must sign those modules (see
# docs/troubleshooting.md#vmware-workstation-kernel-modules).
# https://knowledge.broadcom.com/external/article?articleNumber=368667

module_vmware_workstation_describe() { echo "VMware Workstation Pro ${VMWARE_WORKSTATION_MIN_RELEASE}+ (Broadcom .bundle you download; unattended install)"; }

# _vmware_release_ok <release> — true when a YYHn[uN] release (26H1,
# 26H1u1, 26H2, ...) is at least VMWARE_WORKSTATION_MIN_RELEASE. Pre-2025
# version numbers (17.6.4) do not match the scheme and fail.
_vmware_release_ok() {
  local y h
  [[ "$1" =~ ^([0-9]{2})H([12]) ]] || return 1
  y="${BASH_REMATCH[1]}" h="${BASH_REMATCH[2]}"
  [[ "${VMWARE_WORKSTATION_MIN_RELEASE}" =~ ^([0-9]{2})H([12]) ]] || return 1
  (( 10#$y * 10 + h >= 10#${BASH_REMATCH[1]} * 10 + BASH_REMATCH[2] ))
}

module_vmware_workstation_install() {
  section "VMware Workstation Pro ${VMWARE_WORKSTATION_MIN_RELEASE}"
  local bundle="${DEV_SETUP_VMWARE_BUNDLE:-}" want_sha="${DEV_SETUP_VMWARE_BUNDLE_SHA256:-}" sha version build have
  if [[ -z "$bundle" || ! -f "$bundle" ]]; then
    err "No VMware Workstation Pro bundle given (DEV_SETUP_VMWARE_BUNDLE=${bundle:-<unset>})."
    err "Broadcom requires a (free) support-portal login to download it: sign in at"
    err "https://support.broadcom.com, open My Downloads > VMware Workstation Pro > ${VMWARE_WORKSTATION_MIN_RELEASE} for Linux (latest update),"
    err "download the .bundle, then re-run with DEV_SETUP_VMWARE_BUNDLE=/path/to/it"
    err "(and DEV_SETUP_VMWARE_BUNDLE_SHA256=<the checksum the portal lists>) --vmware-workstation."
    return 1
  fi
  # The bundle runs as root: check it is the file Broadcom published.
  sha="$(sha256sum "$bundle" | cut -d' ' -f1)"
  if [[ -n "$want_sha" ]]; then
    if [[ "${sha}" != "${want_sha,,}" ]]; then
      err "SHA-256 mismatch for ${bundle}: got ${sha}, expected ${want_sha} — not running it."
      return 1
    fi
    ok "Bundle SHA-256 matches DEV_SETUP_VMWARE_BUNDLE_SHA256."
  else
    warn "Bundle SHA-256: ${sha} — compare it with the checksum on Broadcom's download page"
    warn "(set DEV_SETUP_VMWARE_BUNDLE_SHA256 to have the module verify it before running the bundle as root)."
  fi
  # VMware-Workstation-Full-<release>-<build>.x86_64.bundle, e.g. 26H1-25388281.
  version="$(basename "$bundle" | sed -n 's/^VMware-Workstation-Full-\([^-]*\)-\([0-9]*\)\..*/\1/p')"
  build="$(basename "$bundle" | sed -n 's/^VMware-Workstation-Full-\([^-]*\)-\([0-9]*\)\..*/\2/p')"
  have="$(vmware --version 2>/dev/null | sed -n 's/.*build-\([0-9]*\).*/\1/p' || true)"
  log "Bundle: ${bundle} (${version:-unknown version}, build ${build:-unknown})"
  if ! _vmware_release_ok "$version"; then
    err "This module installs VMware Workstation Pro ${VMWARE_WORKSTATION_MIN_RELEASE} or newer; the bundle is '${version:-unknown}'."
    err "(17.x is end of service and lacks the VMSA-2026-0007 fix; 26H1 is the first release supporting Ubuntu 26.04.)"
    err "Download ${VMWARE_WORKSTATION_MIN_RELEASE} (latest update) from Broadcom's portal and point DEV_SETUP_VMWARE_BUNDLE at it."
    return 1
  fi

  # Kernel-module build prerequisites for the running kernel.
  if [[ "$(os_family)" == deb ]]; then
    local meta=linux-headers-amd64
    [[ "${TARGET_OS:-ubuntu}" == ubuntu ]] && meta=linux-headers-generic
    apt_install build-essential "linux-headers-$(uname -r)" \
      || apt_install build-essential "$meta"
  else
    sudo dnf install -y gcc make elfutils-libelf-devel "kernel-devel-$(uname -r)" \
      || sudo dnf install -y gcc make elfutils-libelf-devel kernel-devel
  fi

  if [[ -n "$have" && "$have" == "$build" ]]; then
    ok "VMware Workstation ${version} (build ${build}) already installed."
  else
    if [[ -n "$have" ]]; then
      log "Replacing installed build ${have} with ${version} (build ${build})..."
      sudo vmware-installer -u vmware-workstation --required --console
    fi
    sudo sh "$bundle" --console --eulas-agreed --required
  fi

  # Build and load vmmon/vmnet for the running kernel (needed after every
  # kernel update, too — re-running this module does it).
  if ! sudo vmware-modconfig --console --install-all; then
    warn "vmmon/vmnet did not build for kernel $(uname -r) — see docs/troubleshooting.md#vmware-workstation-kernel-modules."
  fi
  ok "Installed: $(vmware --version 2>/dev/null || echo 'VMware Workstation')"
  log "Start it from the app menu or with 'vmware'; VMs default to ~/vmware."
}

module_vmware_workstation_uninstall() {
  section "Uninstall: VMware Workstation"
  if command_exists vmware-installer; then
    sudo vmware-installer -u vmware-workstation --required --console
  else
    log "VMware Workstation is not installed."
  fi
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.vmware"
    log "Purged ~/.vmware (preferences). Virtual machines (~/vmware) are never deleted — remove them by hand."
  else
    log "Kept: ~/.vmware preferences and every virtual machine (~/vmware)."
  fi
}
