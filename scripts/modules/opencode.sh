# shellcheck shell=bash
# Module: OpenCode — the open-source terminal coding agent (anomalyco,
# formerly sst), via its official v2 install script (latest release, a
# self-contained binary in ~/.opencode/bin), linked into ~/.local/bin.
# Works with hosted providers and local OpenAI-compatible servers
# (llama-server, vLLM, Ollama, Strata). `opencode upgrade` self-updates.
# https://github.com/anomalyco/opencode

module_opencode_describe() { echo "OpenCode (open-source terminal coding agent, official installer, latest)"; }

module_opencode_install() {
  section "OpenCode"
  # --no-modify-path: the ~/.local/bin link below covers PATH instead of
  # another rc-file edit.
  fetch https://opencode.ai/v2/install | bash -s -- --no-modify-path
  ensure_local_bin_path
  mkdir -p "$HOME/.local/bin"
  ln -sf "$HOME/.opencode/bin/opencode" "$HOME/.local/bin/opencode"
  ok "Installed: opencode $("$HOME/.opencode/bin/opencode" --version 2>/dev/null || true)"
  log "Run 'opencode' in a project; '/connect' picks a provider (or point it at a local server)."
}

module_opencode_uninstall() {
  section "Uninstall: OpenCode"
  [[ -L "$HOME/.local/bin/opencode" ]] && rm -f "$HOME/.local/bin/opencode"
  rm -rf "$HOME/.opencode"
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.config/opencode" "$HOME/.local/share/opencode" "$HOME/.cache/opencode"
    log "Purged OpenCode config, data (sessions, auth) and cache."
  else
    log "Kept: ~/.config/opencode and ~/.local/share/opencode (config/sessions — --purge-data removes them)."
  fi
}
