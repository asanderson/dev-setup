# shellcheck shell=bash
# Module: Hermes Agent — Nous Research's self-improving agent CLI, via its
# official install script in non-interactive mode (stable channel). The
# script clones the agent to ~/.hermes/hermes-agent, provisions its own
# pinned uv and Python, and puts a `hermes` launcher in ~/.local/bin.
# `hermes setup` configures providers afterwards.
# https://github.com/NousResearch/hermes-agent

module_hermes_agent_describe() { echo "Hermes Agent (Nous Research agent CLI, official installer)"; }

module_hermes_agent_install() {
  section "Hermes Agent"
  ensure_local_bin_path
  fetch https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive
  ok "Installed: $("$HOME/.local/bin/hermes" --version 2>/dev/null | head -n1 || echo hermes)"
  log "Run 'hermes setup' to pick a model provider (local OpenAI-compatible servers work too)."
}

module_hermes_agent_uninstall() {
  section "Uninstall: Hermes Agent"
  rm -f "$HOME/.local/bin/hermes"
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.hermes"
    log "Purged ~/.hermes (agent code, config, memories, skills)."
  else
    rm -rf "$HOME/.hermes/hermes-agent"
    log "Kept: ~/.hermes config/memories/skills (--purge-data removes them)."
  fi
}
