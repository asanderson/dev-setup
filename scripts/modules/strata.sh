# shellcheck shell=bash
# Module: Strata — the open-source local AI app and inference engine
# (Niko1221/Strata): runs open-weight models on a local NVIDIA/AMD GPU and
# serves OpenAI- and Anthropic-compatible APIs on localhost, so Claude
# Code, Codex and OpenCode can use them. The official installer (latest
# release) verifies the Terminal archive against the release manifest's
# SHA-256 and installs per-user under ~/.local/share/strata with
# ~/.local/bin/strata; `strata launch` fetches the engine and a model.
# https://github.com/Niko1221/Strata

module_strata_describe() { echo "Strata (local LLM app + engine, OpenAI/Anthropic-compatible API, latest)"; }

module_strata_install() {
  section "Strata"
  ensure_local_bin_path
  local tmp; tmp="$(mktemp -d)"
  fetch https://github.com/Niko1221/Strata/releases/latest/download/install.sh -o "${tmp}/install.sh"
  sh "${tmp}/install.sh"
  rm -rf "$tmp"
  ok "Installed: $("$HOME/.local/bin/strata" --version 2>/dev/null || echo strata)"
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
