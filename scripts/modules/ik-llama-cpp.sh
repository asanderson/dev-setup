# shellcheck shell=bash
# Module: ik_llama.cpp — ikawrakow's llama.cpp fork (faster CPU/hybrid
# inference, extra quant types such as IQ*_K and trellis quants, MLA/fused
# MoE paths for DeepSeek-class models). It publishes no releases, so the
# module builds the head of IK_LLAMA_CPP_REF (main by default) from source:
# CUDA when the cuda-toolkit module's nvcc is present, CPU otherwise.
# Per-user under ~/.local/opt/ik_llama.cpp; its binaries share llama.cpp's
# names, so they are linked into ~/.local/bin with an "ik-" prefix
# (ik-llama-server, ik-llama-cli, ...) and both forks coexist.
# https://github.com/ikawrakow/ik_llama.cpp

module_ik_llama_cpp_describe() { echo "ik_llama.cpp (llama.cpp fork, built from main; binaries as ik-llama-*)"; }

module_ik_llama_cpp_install() {
  section "ik_llama.cpp"
  local ref="${IK_LLAMA_CPP_REF:-main}" prefix="$HOME/.local/opt/ik_llama.cpp" f
  build_ggml_project ik_llama.cpp https://github.com/ikawrakow/ik_llama.cpp.git "$ref" "$prefix"
  ensure_local_bin_path
  mkdir -p "$HOME/.local/bin"
  for f in "${prefix}"/bin/llama-*; do
    ln -sf "$f" "$HOME/.local/bin/ik-$(basename "$f")"
  done
  ok "ik_llama.cpp (${ref}): $(cut -c1-12 "${prefix}/.dev-setup-build") — run as ik-llama-server, ik-llama-cli, ..."
}

module_ik_llama_cpp_uninstall() {
  section "Uninstall: ik_llama.cpp"
  local f
  for f in "$HOME"/.local/bin/ik-llama-*; do
    [[ -L "$f" ]] && rm -f "$f"
  done
  rm -rf "$HOME/.local/opt/ik_llama.cpp"
}
