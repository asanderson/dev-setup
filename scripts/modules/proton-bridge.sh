# shellcheck shell=bash
# Module: Proton Mail Bridge — the IMAP/SMTP bridge for desktop mail
# clients. Official .deb resolved from Proton's version feed (no stable
# latest-URL exists for Bridge) and verified against the detached GPG
# signature Proton publishes next to it. Requires a paid Proton Mail plan
# to use; self-updates in place since 3.25.0.

module_proton_bridge_describe() { echo "Proton Mail Bridge (official .deb, latest, GPG-verified — needs a paid plan)"; }

module_proton_bridge_install() {
  section "Proton Mail Bridge"
  command_exists jq || apt_install jq
  local feed deb_url tmp
  feed="$(fetch https://proton.me/download/current_version_linux.json)"
  deb_url="$(jq -r '.DebFile // .stable.DebFile // empty' <<<"$feed")"
  if [[ -z "$deb_url" ]]; then
    err "Could not resolve the latest Bridge .deb from Proton's version feed."
    return 1
  fi
  tmp="$(mktemp -d)"
  fetch "$deb_url" -o "${tmp}/bridge.deb"
  fetch "${deb_url}.sig" -o "${tmp}/bridge.deb.sig"
  fetch "https://proton.me/download/bridge/bridge_pubkey.gpg" -o "${tmp}/bridge_pubkey.gpg"
  gpg --no-default-keyring --keyring "${tmp}/keyring.gpg" \
    --import "${tmp}/bridge_pubkey.gpg" >/dev/null 2>&1
  if ! gpg --no-default-keyring --keyring "${tmp}/keyring.gpg" \
      --verify "${tmp}/bridge.deb.sig" "${tmp}/bridge.deb" >/dev/null 2>&1; then
    rm -rf "$tmp"
    err "GPG signature verification FAILED for the Bridge package — not installing."
    return 1
  fi
  ok "Bridge package signature verified against Proton's published key."
  apt_install "${tmp}/bridge.deb"
  rm -rf "$tmp"
  ok "Installed: $(dpkg-query -W -f='${binary:Package} ${Version}' protonmail-bridge)"
  log "Bridge requires a paid Proton Mail plan. First run: 'protonmail-bridge'"
  log "(or the CLI: 'protonmail-bridge --cli') to log in; it then self-updates."
}
