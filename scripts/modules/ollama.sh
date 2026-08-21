# shellcheck shell=bash
# Module: Ollama — official install script; runs models locally on the RTX 5090.
# https://ollama.com/download/linux

module_ollama_describe() { echo "Ollama (local LLM runtime, NVIDIA GPU accelerated)"; }

module_ollama_install() {
  section "Ollama"
  if ! command_exists nvidia-smi; then
    warn "NVIDIA driver not detected. Ollama will fall back to CPU."
    warn "Install the NVIDIA driver first for GPU acceleration (see github.com/asanderson/dual-boot), then reinstall/restart Ollama."
    confirm "Continue installing Ollama anyway?" n || return 0
  fi

  # The vendor installer extracts a zstd-compressed bundle and exits if
  # zstd is missing — fresh Ubuntu installs don't ship it.
  apt_install zstd

  fetch https://ollama.com/install.sh | sh

  sudo systemctl enable --now ollama 2>/dev/null || true
  ok "Installed: $(ollama --version 2>/dev/null || echo 'ollama (service starting)')"
  log "Try it: 'ollama run llama3.2' — with the RTX 5090's 24GB VRAM, larger models like"
  log "'ollama run qwen3:32b' are practical. Models are stored under /usr/share/ollama."
}

module_ollama_uninstall() {
  section "Uninstall: Ollama"
  sudo systemctl disable --now ollama 2>/dev/null || true
  sudo rm -f /etc/systemd/system/ollama.service /usr/local/bin/ollama /usr/bin/ollama
  sudo rm -rf /usr/local/lib/ollama /usr/lib/ollama
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    sudo rm -rf /usr/share/ollama "$HOME/.ollama"
    sudo userdel ollama 2>/dev/null || true
    log "Purged models (/usr/share/ollama, ~/.ollama) and the service user."
  else
    log "Kept: downloaded models (--purge-data removes them)."
  fi
}
