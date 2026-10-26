# shellcheck shell=bash
# Module: KTransformers — kvcache-ai's CPU/GPU hybrid inference for huge
# MoE models (experts on CPU via AMX/AVX-512 kernels, attention on the
# GPU), served through its SGLang fork. Current upstream layout: the
# kt-kernel package (pinned by the `ktransformers` wrapper, which also
# brings the `kt` CLI) plus sglang-kt, from PyPI into a dedicated uv
# virtualenv (~/.local/opt/ktransformers, Python 3.12). Its wheels are
# manylinux_2_35 — glibc 2.35+, i.e. Ubuntu 26.04 and Debian 13 here, not
# EL9 (2.34) — and need an NVIDIA GPU + driver to run.
# https://github.com/kvcache-ai/ktransformers

module_ktransformers_describe() { echo "KTransformers (CPU/GPU hybrid MoE inference via kt-kernel + SGLang fork)"; }

module_ktransformers_install() {
  section "KTransformers"
  require_uv ktransformers
  local venv="$HOME/.local/opt/ktransformers"
  has_nvidia_gpu || warn "No NVIDIA GPU detected: KTransformers installs, but serving needs a GPU + driver."
  [[ -x "${venv}/bin/python" ]] || uv venv --quiet --python 3.12 --seed "$venv"
  uv pip install --quiet --python "${venv}/bin/python" --upgrade ktransformers sglang-kt
  ensure_local_bin_path
  [[ -x "${venv}/bin/kt" ]] && ln -sf "${venv}/bin/kt" "$HOME/.local/bin/kt"
  ok "Installed: kt-kernel $("${venv}/bin/python" -c 'import importlib.metadata as m; print(m.version("kt-kernel"))')"
  log "Check the machine with 'kt doctor'; serve with ${venv}/bin/python -m sglang.launch_server --kt-method ..."
  log "Upstream lists SM 80/86/89/90 GPUs; RTX 50-series (sm_120) support is not listed yet."
}

module_ktransformers_uninstall() {
  section "Uninstall: KTransformers"
  [[ -L "$HOME/.local/bin/kt" ]] && rm -f "$HOME/.local/bin/kt"
  rm -rf "$HOME/.local/opt/ktransformers"
  log "Removed the KTransformers virtualenv (model weights you downloaded are untouched)."
}
