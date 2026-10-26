# shellcheck shell=bash
# Module: Oh My Pi (omp) — Can Bölük's batteries-included fork of Mario
# Zechner's Pi coding agent, via its official install script (latest).
# With Bun >= 1.3.14 on PATH (the nodejs module installs it) the script
# runs `bun install -g @oh-my-pi/pi-coding-agent`; without it, it drops a
# SHA-256-verified standalone binary at ~/.local/bin/omp.
# https://github.com/can1357/oh-my-pi

module_oh_my_pi_describe() { echo "Oh My Pi (omp coding agent, official installer, latest)"; }

module_oh_my_pi_install() {
  section "Oh My Pi"
  [[ -x "$HOME/.bun/bin/bun" ]] && export PATH="$HOME/.bun/bin:$PATH"
  ensure_local_bin_path
  fetch https://omp.sh/install | sh
  ok "Installed: $(omp --version 2>/dev/null || echo omp)"
  log "Run 'omp' in a project; models and providers live in ~/.omp/agent/models.yml."
}

module_oh_my_pi_uninstall() {
  section "Uninstall: Oh My Pi"
  if [[ -x "$HOME/.bun/bin/bun" ]]; then
    "$HOME/.bun/bin/bun" remove -g @oh-my-pi/pi-coding-agent >/dev/null 2>&1 || true
  fi
  rm -f "$HOME/.local/bin/omp"
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.omp"
    log "Purged ~/.omp (config, models, sessions)."
  else
    log "Kept: ~/.omp (config/models/sessions — --purge-data removes it)."
  fi
}
