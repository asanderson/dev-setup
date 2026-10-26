# shellcheck shell=bash
# Module: Codex — OpenAI's coding agent CLI, via OpenAI's standalone
# installer (latest release; static musl build, so identical on every
# target OS). It installs ~/.local/bin/codex, linked into
# ~/.codex/packages/standalone. When the installer host is unreachable the
# module falls back to the same static binary from the latest GitHub
# release. Sign in on first run (ChatGPT plan or API key).
# https://github.com/openai/codex

module_codex_describe() { echo "Codex (OpenAI's coding agent CLI, official installer, latest)"; }

module_codex_install() {
  section "Codex"
  ensure_local_bin_path
  if ! fetch https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh; then
    warn "OpenAI's installer was unreachable — installing the static binary from the latest GitHub release."
    local tmp; tmp="$(mktemp -d)"
    fetch https://github.com/openai/codex/releases/latest/download/codex-x86_64-unknown-linux-musl.tar.gz \
      -o "${tmp}/codex.tar.gz"
    tar -xzf "${tmp}/codex.tar.gz" -C "$tmp"
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "${tmp}/codex-x86_64-unknown-linux-musl" "$HOME/.local/bin/codex"
    rm -rf "$tmp"
  fi
  ok "Installed: $("$HOME/.local/bin/codex" --version 2>/dev/null || echo codex)"
  log "Run 'codex' in a project directory to sign in (ChatGPT plan or OpenAI API key)."
}

module_codex_uninstall() {
  section "Uninstall: Codex"
  rm -f "$HOME/.local/bin/codex"
  rm -rf "$HOME/.codex/packages/standalone"
  # The installer may add a marked PATH block to shell profiles.
  sed -i '/# >>> Codex installer >>>/,/# <<< Codex installer <<</d' \
    "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc" 2>/dev/null || true
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.codex"
    log "Purged ~/.codex (config, credentials, session history)."
  else
    log "Kept: ~/.codex (config/credentials/history — --purge-data removes it)."
  fi
}
