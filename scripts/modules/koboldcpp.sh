# shellcheck shell=bash
# Module: KoboldCpp — LostRuins' single-file llama.cpp-based runner with a
# bundled web UI and KoboldAI/OpenAI-compatible APIs. Installs the newest
# release's self-contained Linux binary (KOBOLDCPP_VERSION pins a tag):
# the CUDA build when an NVIDIA GPU is present, the nocuda build
# otherwise. Per-user under ~/.local/opt/koboldcpp, linked into
# ~/.local/bin/koboldcpp.
# https://github.com/LostRuins/koboldcpp

module_koboldcpp_describe() { echo "KoboldCpp (single-file GGUF runner + web UI, newest release)"; }

module_koboldcpp_install() {
  section "KoboldCpp"
  local tag="${KOBOLDCPP_VERSION:-latest}" asset=koboldcpp-linux-x64 dir="$HOME/.local/opt/koboldcpp"
  has_nvidia_gpu || asset=koboldcpp-linux-x64-nocuda
  if [[ "$tag" == latest ]]; then
    tag="$(github_latest_tag LostRuins/koboldcpp "$asset")"
    [[ -n "$tag" ]] || { err "Could not resolve the newest KoboldCpp release; pin KOBOLDCPP_VERSION in config/versions.env."; return 1; }
  fi
  if [[ -x "${dir}/koboldcpp" && "$(cat "${dir}/VERSION" 2>/dev/null)" == "${tag} ${asset}" ]]; then
    ok "KoboldCpp ${tag} (${asset}) already installed."
  else
    mkdir -p "$dir"
    fetch "https://github.com/LostRuins/koboldcpp/releases/download/${tag}/${asset}" -o "${dir}/koboldcpp.part"
    chmod +x "${dir}/koboldcpp.part"
    mv -f "${dir}/koboldcpp.part" "${dir}/koboldcpp"
    echo "${tag} ${asset}" > "${dir}/VERSION"
  fi
  ensure_local_bin_path
  mkdir -p "$HOME/.local/bin"
  ln -sf "${dir}/koboldcpp" "$HOME/.local/bin/koboldcpp"
  ok "Installed: KoboldCpp ${tag} (${asset})"
  log "Run: koboldcpp --model model.gguf --gpulayers 99  (web UI on http://localhost:5001)"
}

module_koboldcpp_uninstall() {
  section "Uninstall: KoboldCpp"
  [[ -L "$HOME/.local/bin/koboldcpp" ]] && rm -f "$HOME/.local/bin/koboldcpp"
  rm -rf "$HOME/.local/opt/koboldcpp"
}
