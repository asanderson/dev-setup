# shellcheck shell=bash
# Module: llama.cpp — ggml-org's C/C++ LLM inference engine (llama-cli,
# llama-server, llama-bench, ...), built from source at the newest release
# tag (LLAMA_CPP_VERSION in versions.env pins one instead). CUDA offload
# when the cuda-toolkit module's nvcc is present, tuned to the local GPU;
# CPU backend otherwise. Per-user under ~/.local/opt/llama.cpp, binaries
# linked into ~/.local/bin.
# https://github.com/ggml-org/llama.cpp

module_llama_cpp_describe() { echo "llama.cpp (built from the newest release; CUDA when the toolkit is present)"; }

LLAMA_CPP_REPO="https://github.com/ggml-org/llama.cpp.git"

# llama_cpp_build_number <tag>: the number N of the b<N> release tag on the
# same commit as <tag> (v1.0.0 is b12359), or nothing when there is none.
# Upstream derives the build number from the commit count, which the
# shallow clone cannot see (it counts 1), and the build uses that number to
# fetch the prebuilt web UI published for the release: asking for b1 misses
# and falls back to the newest UI, which a release need not understand.
llama_cpp_build_number() {
  git ls-remote --tags "$LLAMA_CPP_REPO" 2>/dev/null | awk -v ref="refs/tags/$1" '
    $2 == ref && !c       { c = $1 }   # lightweight tag, or an annotated tag object
    $2 == ref "^{}"       { c = $1 }   # the commit an annotated tag points at
    $2 ~ /^refs\/tags\/b[0-9]+$/ { b[$1] = substr($2, 12) }
    END                   { if (c in b) print b[c] }' || true
}

module_llama_cpp_install() {
  section "llama.cpp"
  local ref="${LLAMA_CPP_VERSION:-latest}" prefix="$HOME/.local/opt/llama.cpp" f build_number
  if [[ "$ref" == latest ]]; then
    ref="$(github_latest_tag ggml-org/llama.cpp nightly-tag.txt)"
    [[ -n "$ref" ]] || { err "Could not resolve the newest llama.cpp release; pin LLAMA_CPP_VERSION in config/versions.env."; return 1; }
  fi
  build_number="$(llama_cpp_build_number "$ref")"
  [[ -n "$build_number" ]] \
    || warn "llama.cpp: no b<N> release tag on ${ref}'s commit; the build may embed a web UI from another release."
  build_ggml_project llama.cpp "$LLAMA_CPP_REPO" "$ref" "$prefix" \
    ${build_number:+"-DLLAMA_BUILD_NUMBER=${build_number}"}
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
