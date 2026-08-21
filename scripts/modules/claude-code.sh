# shellcheck shell=bash
# Module: Claude Code — Anthropic's agentic coding CLI, via the native installer.
# https://code.claude.com/docs/en/setup

module_claude_code_describe() { echo "Claude Code (native installer, auto-updating)"; }

module_claude_code_install() {
  section "Claude Code"
  # The native installer is self-contained (no Node.js required) and keeps
  # itself up to date. It installs to ~/.local/bin/claude.
  fetch https://claude.ai/install.sh | bash

  # Ensure ~/.local/bin is on PATH for future shells.
  if ! grep -qs '\.local/bin' "$HOME/.bashrc" && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    # shellcheck disable=SC2016
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    warn "Added ~/.local/bin to PATH in ~/.bashrc (takes effect in new shells)."
  fi

  if [[ -x "$HOME/.local/bin/claude" ]]; then
    ok "Installed: $("$HOME/.local/bin/claude" --version 2>/dev/null || echo 'claude (version check needs a login)')"
    log "Run 'claude' in a project directory to log in (Claude subscription or Console account)."
  else
    err "claude binary not found after install; check the installer output above."
    return 1
  fi
}

module_claude_code_uninstall() {
  section "Uninstall: Claude Code"
  rm -f "$HOME/.local/bin/claude"
  rm -rf "$HOME/.local/share/claude"
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.claude" "$HOME/.claude.json"
    log "Purged ~/.claude (config, history, plugins)."
  else
    log "Kept: ~/.claude (config/history — --purge-data removes it)."
  fi
}
