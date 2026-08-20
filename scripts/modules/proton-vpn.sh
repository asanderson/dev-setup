# shellcheck shell=bash
# Module: Proton VPN — the official Proton apt repository (the one Proton
# product with a real apt repo), GNOME desktop app. The repo-setup package
# is checksum-pinned in versions.env against the sha256 Proton publishes on
# their install page; afterwards the app tracks latest via apt like any
# repo-backed tool.

module_proton_vpn_describe() { echo "Proton VPN (official apt repo, GNOME desktop app)"; }

module_proton_vpn_install() {
  section "Proton VPN"
  local tmp; tmp="$(mktemp -d)"
  fetch "$PROTON_VPN_RELEASE_DEB" -o "${tmp}/pvpn-release.deb"
  if ! echo "${PROTON_VPN_RELEASE_DEB_SHA256}  ${tmp}/pvpn-release.deb" | sha256sum -c - >/dev/null 2>&1; then
    rm -rf "$tmp"
    err "Checksum mismatch on the Proton VPN repo-setup package — refusing to install."
    err "If Proton shipped a new repo-setup release, update PROTON_VPN_RELEASE_DEB[_SHA256]"
    err "in config/versions.env from https://protonvpn.com/support/official-linux-vpn-ubuntu/"
    return 1
  fi
  apt_install "${tmp}/pvpn-release.deb"
  rm -rf "$tmp"
  _APT_UPDATED=""   # new apt source just landed
  apt_install proton-vpn-gnome-desktop

  ok "Installed: $(dpkg-query -W -f='${binary:Package} ${Version}' proton-vpn-gnome-desktop)"
  log "Official CLI alternative: 'sudo apt install proton-vpn-cli' — but don't run"
  log "the GUI and CLI at the same time (Proton documents them as exclusive)."
}
