# shellcheck shell=bash
# Module: VMware Workstation 17 Pro — Broadcom's desktop hypervisor (free
# for commercial, educational and personal use). Broadcom serves the
# installer only behind a (free) Broadcom support-portal login, so there is
# no URL to fetch: download the Linux .bundle yourself, then point the
# module at it with DEV_SETUP_VMWARE_BUNDLE=/path/to/bundle — or leave it
# in ~/Downloads, where the newest VMware-Workstation-Full-*.x86_64.bundle
# is picked up. 17.6.4 is the final 17.x release (end of service Nov 2025);
# the same module installs its successors (25H2, 26H1 — the first with
# Ubuntu 26.04 host support) when that is the bundle you supply. The bundle
# is a distro-agnostic installer; the module adds the kernel-module build
# prerequisites, runs it unattended and builds vmmon/vmnet for the running
# kernel. Secure Boot machines must sign those modules (see
# docs/troubleshooting.md#vmware-workstation-kernel-modules).
# https://knowledge.broadcom.com/external/article?articleNumber=368667

module_vmware_workstation_describe() { echo "VMware Workstation 17 Pro (Broadcom .bundle you download; unattended install)"; }

# The bundle to install: DEV_SETUP_VMWARE_BUNDLE, else the newest
# Workstation bundle in ~/Downloads.
_vmware_bundle() {
  if [[ -n "${DEV_SETUP_VMWARE_BUNDLE:-}" ]]; then
    echo "$DEV_SETUP_VMWARE_BUNDLE"
    return
  fi
  # `|| true`: no ~/Downloads must mean "no bundle", not a pipefail exit
  # that would end the module before its guidance prints.
  find "$HOME/Downloads" -maxdepth 1 -type f -name 'VMware-Workstation-Full-*.x86_64.bundle' 2>/dev/null \
    | sort -V | tail -n1 || true
}

module_vmware_workstation_install() {
  section "VMware Workstation 17 Pro"
  local bundle version build have
  bundle="$(_vmware_bundle)"
  if [[ -z "$bundle" || ! -f "$bundle" ]]; then
    err "No VMware Workstation Pro bundle found."
    err "Broadcom requires a (free) support-portal login to download it: sign in at"
    err "https://support.broadcom.com, open My Downloads > VMware Workstation Pro > 17.x for Linux,"
    err "save the .bundle to ~/Downloads (or set DEV_SETUP_VMWARE_BUNDLE=/path/to/it), and re-run --vmware-workstation."
    return 1
  fi
  # VMware-Workstation-Full-<version>-<build>.x86_64.bundle, version 17.6.4 or 26H1.
  version="$(basename "$bundle" | sed -n 's/^VMware-Workstation-Full-\([^-]*\)-\([0-9]*\)\..*/\1/p')"
  build="$(basename "$bundle" | sed -n 's/^VMware-Workstation-Full-\([^-]*\)-\([0-9]*\)\..*/\2/p')"
  have="$(vmware --version 2>/dev/null | sed -n 's/.*build-\([0-9]*\).*/\1/p' || true)"
  log "Bundle: ${bundle} (${version:-unknown version}, build ${build:-unknown})"
  if [[ "$version" == 17.* ]]; then
    warn "Workstation 17.x reached end of service in Nov 2025 and receives no more security fixes"
    warn "(VMSA-2026-0007 is fixed only in 26H1u1+); 26H1 is also the first release supporting Ubuntu 26.04 hosts."
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
