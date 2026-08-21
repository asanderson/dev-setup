# shellcheck shell=bash
# Module: Proton Mail Bridge — the IMAP/SMTP bridge for desktop mail
# clients. Official .deb resolved from Proton's version feed (no stable
# latest-URL exists for Bridge) and verified against the detached GPG
# signature Proton publishes next to it. Requires a paid Proton Mail plan
# to use; self-updates in place since 3.25.0.

module_proton_bridge_describe() { echo "Proton Mail Bridge (official package, latest, GPG-verified — needs a paid plan)"; }

module_proton_bridge_install() {
  section "Proton Mail Bridge"
  if ! command_exists jq; then
    if [[ "$(os_family)" == deb ]]; then apt_install jq; else sudo dnf install -y jq; fi
  fi
  local feed pkg_url tmp
  feed="$(fetch https://proton.me/download/current_version_linux.json)"
  if [[ "$(os_family)" == deb ]]; then
    pkg_url="$(jq -r '.DebFile // .stable.DebFile // empty' <<<"$feed")"
  else
    pkg_url="$(jq -r '.RpmFile // .stable.RpmFile // empty' <<<"$feed")"
  fi
  if [[ -z "$pkg_url" ]]; then
    err "Could not resolve the latest Bridge package from Proton's version feed."
    return 1
  fi
  tmp="$(mktemp -d)"
  fetch "$pkg_url" -o "${tmp}/bridge.pkg"
  fetch "${pkg_url}.sig" -o "${tmp}/bridge.pkg.sig"
  fetch "https://proton.me/download/bridge/bridge_pubkey.gpg" -o "${tmp}/bridge_pubkey.gpg"
  gpg --no-default-keyring --keyring "${tmp}/keyring.gpg" \
    --import "${tmp}/bridge_pubkey.gpg" >/dev/null 2>&1
  if ! gpg --no-default-keyring --keyring "${tmp}/keyring.gpg" \
      --verify "${tmp}/bridge.pkg.sig" "${tmp}/bridge.pkg" >/dev/null 2>&1; then
    rm -rf "$tmp"
    err "GPG signature verification FAILED for the Bridge package — not installing."
    return 1
  fi
  ok "Bridge package signature verified against Proton's published key."
  if [[ "$(os_family)" == deb ]]; then
    mv "${tmp}/bridge.pkg" "${tmp}/bridge.deb"
    apt_install "${tmp}/bridge.deb"
  else
    mv "${tmp}/bridge.pkg" "${tmp}/bridge.rpm"
    sudo dnf install -y "${tmp}/bridge.rpm"
  fi
  rm -rf "$tmp"
  ok "Installed: protonmail-bridge $(command -v dpkg-query >/dev/null && dpkg-query -W -f='${Version}' protonmail-bridge 2>/dev/null || rpm -q --qf '%{VERSION}' protonmail-bridge 2>/dev/null || true)"
  log "Bridge requires a paid Proton Mail plan. First run: 'protonmail-bridge'"
  log "(or the CLI: 'protonmail-bridge --cli') to log in; it then self-updates."
}

module_proton_bridge_uninstall() {
  section "Uninstall: Proton Mail Bridge"
  if [[ "$(os_family)" == deb ]]; then
    sudo apt-get remove -y protonmail-bridge 2>/dev/null || true
  else
    sudo dnf remove -y protonmail-bridge 2>/dev/null || true
  fi
}
