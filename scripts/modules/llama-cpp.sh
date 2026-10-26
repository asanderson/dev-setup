# shellcheck shell=bash
# Module: llama.cpp — ggml-org's C/C++ LLM inference engine (llama-cli,
# llama-server, llama-bench, ...), built from source at the newest release
# tag (LLAMA_CPP_VERSION in versions.env pins one instead). CUDA offload
# when the cuda-toolkit module's nvcc is present, tuned to the local GPU;
# CPU backend otherwise. Per-user under ~/.local/opt/llama.cpp, binaries
# linked into ~/.local/bin.
# https://github.com/ggml-org/llama.cpp

module_llama_cpp_describe() { echo "llama.cpp (built from the newest release; CUDA when the toolkit is present)"; }

module_llama_cpp_install() {
  section "llama.cpp"
  local ref="${LLAMA_CPP_VERSION:-latest}" prefix="$HOME/.local/opt/llama.cpp" f
  if [[ "$ref" == latest ]]; then
    ref="$(github_latest_tag ggml-org/llama.cpp nightly-tag.txt)"
    [[ -n "$ref" ]] || { err "Could not resolve the newest llama.cpp release; pin LLAMA_CPP_VERSION in config/versions.env."; return 1; }
  fi
  build_ggml_project llama.cpp https://github.com/ggml-org/llama.cpp.git "$ref" "$prefix"
  ensure_local_bin_path
  mkdir -p "$HOME/.local/bin"
  for f in "${prefix}"/bin/llama-*; do
    ln -sf "$f" "$HOME/.local/bin/$(basename "$f")"
  done
  ok "llama.cpp ${ref}: $("$HOME/.local/bin/llama-cli" --version 2>&1 | grep -m1 -i version || echo installed)"
  log "Serve a GGUF with an OpenAI-compatible API: llama-server -m model.gguf -ngl 99"
  log "(or pull one straight from Hugging Face: llama-server -hf <user>/<repo>:<quant>)."
}

module_llama_cpp_uninstall() {
  section "Uninstall: llama.cpp"
  local f
  for f in "$HOME"/.local/bin/llama-*; do
    [[ -L "$f" && "$(readlink "$f")" == "$HOME/.local/opt/llama.cpp/"* ]] && rm -f "$f"
  done
  rm -rf "$HOME/.local/opt/llama.cpp"
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.cache/llama.cpp"
    log "Purged ~/.cache/llama.cpp (models fetched with -hf)."
  else
    log "Kept: ~/.cache/llama.cpp (models fetched with -hf — --purge-data removes them)."
  fi
}
