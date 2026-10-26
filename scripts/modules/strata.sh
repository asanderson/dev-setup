# shellcheck shell=bash
# Module: Strata — the open-source local AI app and inference engine
# (Niko1221/Strata): runs open-weight models on a local NVIDIA/AMD GPU and
# serves OpenAI- and Anthropic-compatible APIs on localhost, so Claude
# Code, Codex and OpenCode can use them. The release is pinned
# (STRATA_VERSION in versions.env): the official installer script is
# SHA-256 verified (STRATA_INSTALL_SH_SHA256) before it runs, and
# STRATA_FEED points it at that same release, whose manifest SHA-256 it
# checks the Terminal archive against. Per-user under
# ~/.local/share/strata with ~/.local/bin/strata; `strata launch` fetches
# the engine and a model.
# https://github.com/Niko1221/Strata

module_strata_describe() { echo "Strata ${STRATA_VERSION} (local LLM app + engine, OpenAI/Anthropic-compatible API)"; }

module_strata_install() {
  section "Strata"
  ensure_local_bin_path
  local feed="https://github.com/Niko1221/Strata/releases/download/${STRATA_VERSION}" tmp
  tmp="$(mktemp -d)"
  fetch "${feed}/install.sh" -o "${tmp}/install.sh"
  echo "${STRATA_INSTALL_SH_SHA256}  ${tmp}/install.sh" | sha256sum -c --quiet - \
    || { rm -rf "$tmp"; err "Strata ${STRATA_VERSION} install.sh failed its SHA-256 check — not running it."; return 1; }
  STRATA_FEED="$feed" sh "${tmp}/install.sh"
  rm -rf "$tmp"
  ok "Installed: Strata ${STRATA_VERSION} ($("$HOME/.local/bin/strata" --version 2>/dev/null || echo terminal))"
  has_nvidia_gpu || warn "No NVIDIA GPU detected: Strata's engine needs an NVIDIA or AMD GPU to run models."
  log "Next: 'strata launch' (fetches the engine + a model), then 'strata connect' for"
  log "Claude Code / Codex / OpenCode setup against the local API."
}

module_strata_uninstall() {
  section "Uninstall: Strata"
  [[ -L "$HOME/.local/bin/strata" ]] && rm -f "$HOME/.local/bin/strata"
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.local/share/strata"
    log "Purged ~/.local/share/strata (terminal, engine, downloaded models)."
  else
    rm -rf "$HOME/.local/share/strata/terminal"
    log "Kept: ~/.local/share/strata engine + models (--purge-data removes them)."
  fi
}
