# shellcheck shell=bash
# Module: vLLM — high-throughput LLM serving (OpenAI-compatible server),
# the newest release from PyPI into a dedicated uv-managed virtualenv
# (~/.local/opt/vllm, Python 3.12) as vLLM's docs prescribe, with the
# matching PyTorch CUDA build picked by uv's --torch-backend=auto. Linux
# + NVIDIA GPU (compute capability 7.5+) only; the wheels bundle the CUDA
# runtime, so the host needs only a recent driver (R580+ for the CUDA 13
# builds) — no toolkit. `vllm` is linked into ~/.local/bin.
# https://docs.vllm.ai/en/latest/getting_started/installation/gpu/

module_vllm_describe() { echo "vLLM (LLM serving engine, newest release, uv virtualenv)"; }

module_vllm_install() {
  section "vLLM"
  require_uv vllm
  local venv="$HOME/.local/opt/vllm"
  local -a backend=()
  if has_nvidia_gpu; then
    backend=(--torch-backend=auto)
  else
    warn "No NVIDIA GPU detected: installing vLLM's default CUDA wheels; serving needs a GPU + driver."
  fi
  [[ -x "${venv}/bin/python" ]] || uv venv --quiet --python 3.12 --seed "$venv"
  uv pip install --quiet --python "${venv}/bin/python" --upgrade vllm "${backend[@]}"
  ensure_local_bin_path
  ln -sf "${venv}/bin/vllm" "$HOME/.local/bin/vllm"
  if nvidia-smi >/dev/null 2>&1; then
    "${venv}/bin/vllm" download-kernels >/dev/null 2>&1 \
      || log "Optional FlashInfer kernel prefetch skipped (vllm download-kernels)."
  fi
  ok "Installed: vLLM $("${venv}/bin/python" -c 'import importlib.metadata as m; print(m.version("vllm"))')"
  log "Serve: vllm serve <hf-model> (OpenAI-compatible API on http://localhost:8000)."
}

module_vllm_uninstall() {
  section "Uninstall: vLLM"
  [[ -L "$HOME/.local/bin/vllm" ]] && rm -f "$HOME/.local/bin/vllm"
  rm -rf "$HOME/.local/opt/vllm"
  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    rm -rf "$HOME/.cache/vllm"
    log "Purged ~/.cache/vllm (compile and kernel caches)."
  else
    log "Kept: ~/.cache/vllm and the shared Hugging Face cache (~/.cache/huggingface)."
  fi
}
