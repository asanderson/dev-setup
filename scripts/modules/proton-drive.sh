# shellcheck shell=bash
# Module: Proton Drive CLI — Proton ships NO Linux GUI app for Drive yet
# (announced as in development for late 2026); the official Proton Drive
# CLI is the supported Linux client. Static binary resolved from Proton's
# version feed and verified against the SHA512 it publishes there.

module_proton_drive_describe() { echo "Proton Drive CLI (official binary, latest, SHA512-verified — Drive has no Linux GUI app yet)"; }

module_proton_drive_install() {
  section "Proton Drive CLI"
  command_exists jq || apt_install jq
  # Keyring integration: the CLI stores tokens via libsecret over D-Bus.
  apt_install libsecret-1-0

  local feed url sha tmp
  feed="$(fetch https://proton.me/download/drive/cli/version.json)"
  read -r url sha < <(jq -r '
    [.. | objects | select(has("Url")) | select(.Url | test("linux-x64/proton-drive$"))][0]
    | "\(.Url) \(.Sha512CheckSum // .Sha512 // "")"' <<<"$feed")
  if [[ -z "${url:-}" || "$url" == "null" ]]; then
    err "Could not resolve the latest Proton Drive CLI from Proton's version feed."
    return 1
  fi
  tmp="$(mktemp -d)"
  fetch "$url" -o "${tmp}/proton-drive"
  if [[ -n "${sha:-}" ]]; then
    echo "${sha}  ${tmp}/proton-drive" | sha512sum -c - >/dev/null 2>&1 \
      || { rm -rf "$tmp"; err "SHA512 mismatch on the Proton Drive CLI download."; return 1; }
    ok "Proton Drive CLI checksum verified."
  else
    warn "Version feed carried no SHA512 for this file — installing on TLS trust only."
  fi
  sudo install -m 0755 "${tmp}/proton-drive" /usr/local/bin/proton-drive
  rm -rf "$tmp"
  ok "Installed: /usr/local/bin/proton-drive ($(proton-drive --version 2>/dev/null | head -n1 || echo 'version prints on first run'))"
  log "Log in with 'proton-drive auth login' — it opens a browser flow, so do"
  log "that interactively (headless machines: see Proton's drive-cli support page)."
}
