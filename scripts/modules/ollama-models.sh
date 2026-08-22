# shellcheck shell=bash
# Module: Ollama coding models — pulls the verified local coding stack and
# creates pinned-context variants of each.
#
# The picks and the context sizes below are tuned for a 24GB-VRAM machine
# (RTX 5090 Laptop). They come from a benchmark review that discarded two
# widely-circulated but unverifiable numbers, so the short version of why
# these three:
#
#   gpt-oss:20b            MXFP4 is OpenAI's native release format, so the
#                          local file is bit-identical to the benchmarked
#                          artifact — no requant lottery. The only pick that
#                          holds a full 131K context in 24GB (measured 3GiB
#                          KV) with headroom, at ~150 tok/s.
#   gemma4:26b-a4b-it-qat  The 26B MoE, not the 31B dense: the 31B's sliding
#                          -window layers burn a fixed 3.12GiB of KV and cap
#                          it near 32-40K here. QAT counters the Q4 coding
#                          degradation the community reports.
#   laguna-xs-2.1          Post-trained specifically for agentic coding; its
#                          third-party Terminal-Bench score beats larger
#                          models' official ones. 20GB of weights is tight on
#                          24GB — this module starts it at 32K and tells you
#                          how to walk it up.
#
# Ollama silently truncates prompts past num_ctx rather than erroring, and
# its default varies with detected VRAM — a 24GB card sits exactly on an
# internal boundary. That is why every model here gets an explicit pinned
# variant instead of relying on the default.
#
# Opt-in extra: DEV_SETUP_OLLAMA_NEMOTRON=1 also fetches NVIDIA's
# Nemotron 3 Nano at IQ4_XS from Hugging Face (the Ollama-library tag is
# Q4_K_M at 24GB, which cannot fit a 24GB card). It has the strongest
# published long-context evidence of the set.

module_ollama_models_describe() { echo "Ollama coding models (gpt-oss 20B, Gemma 4 26B, Laguna XS — pinned-context variants, ~50GB)"; }

# tag|variant|num_ctx|approx GB|description
_ollama_model_picks() {
  cat <<'PICKS'
gpt-oss:20b|gptoss20b-128k|131072|14|OpenAI gpt-oss 20B (MXFP4, native quant) — daily driver, ~150 tok/s
gemma4:26b-a4b-it-qat|gemma26b-128k|131072|16|Google Gemma 4 26B MoE (QAT) — long-context comprehension
laguna-xs-2.1|laguna-32k|32768|20|Poolside Laguna XS 2.1 — agentic coding challenger
PICKS
}

# Serving config the pinned contexts depend on. Applied as a systemd
# drop-in so it survives Ollama upgrades and is trivially removable.
_ollama_models_apply_serving_config() {
  local dropin=/etc/systemd/system/ollama.service.d/10-dev-setup-kv.conf
  sudo install -d -m 0755 /etc/systemd/system/ollama.service.d
  sudo tee "$dropin" >/dev/null <<'EOF'
# Written by dev-setup (ollama-models module).
# q8_0 KV roughly halves cache memory, which is what makes the pinned
# context sizes fit. If output quality degrades on a given model, drop
# OLLAMA_KV_CACHE_TYPE and lower that model's num_ctx instead.
[Service]
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="OLLAMA_KEEP_ALIVE=30m"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
EOF
  sudo systemctl daemon-reload 2>/dev/null || true
  sudo systemctl restart ollama 2>/dev/null || true
  ok "Serving config applied (flash attention, q8_0 KV cache, single loaded model)."
}

# Bounded wait — pulls talk to the daemon, which may still be restarting.
_ollama_models_wait_ready() {
  local host="${OLLAMA_HOST:-127.0.0.1:11434}"
  host="${host#http://}"; host="${host#https://}"
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 2 "http://${host}/api/version" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

_ollama_models_vram_mb() {
  local out
  command_exists nvidia-smi || { echo 0; return 0; }
  # Capture then truncate: `| head -n1` inside a pipefail pipeline SIGPIPEs
  # multi-GPU output into a spurious failure.
  out="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null || true)"
  out="${out%%$'\n'*}"
  [[ "$out" =~ ^[0-9]+$ ]] && echo "$out" || echo 0
}

module_ollama_models_install() {
  section "Ollama coding models"

  command_exists ollama \
    || die "Ollama is not installed — run this installer with --ollama first (or select Ollama in the menu)."

  _ollama_models_apply_serving_config
  _ollama_models_wait_ready \
    || die "The Ollama API did not come up at ${OLLAMA_HOST:-127.0.0.1:11434}. Check: systemctl status ollama"

  local vram_mb; vram_mb="$(_ollama_models_vram_mb)"
  if [[ "$vram_mb" -eq 0 ]]; then
    warn "No NVIDIA GPU detected — these models will run on CPU at a small fraction of the quoted speeds."
  elif [[ "$vram_mb" -lt 23000 ]]; then
    warn "Detected ${vram_mb} MiB of VRAM. The pinned context sizes here are tuned for 24GB;"
    warn "on a smaller card Ollama will offload layers to the CPU. Lower num_ctx per model if so."
  else
    log "Detected ${vram_mb} MiB of VRAM — the pinned context sizes below are sized for this."
  fi

  # ~50GB of weights: fail early rather than half-way through the third pull.
  local avail_gb
  avail_gb="$(df -BG --output=avail /usr/share/ollama 2>/dev/null | tail -n1 | tr -dc '0-9')"
  [[ -n "$avail_gb" ]] || avail_gb="$(df -BG --output=avail / | tail -n1 | tr -dc '0-9')"
  if [[ -n "$avail_gb" && "$avail_gb" -lt 60 ]]; then
    warn "Only ${avail_gb} GB free where Ollama stores models; the full set needs ~50GB."
    confirm "Continue anyway?" n || return 0
  fi

  local tag variant ctx gb desc tmp
  local -a failed=() installed=()
  while IFS='|' read -r tag variant ctx gb desc; do
    [[ -n "$tag" ]] || continue
    confirm "Pull ${desc} [~${gb}GB]?" y || { log "Skipped ${tag}."; continue; }

    if ! ollama pull "$tag"; then
      err "Failed to pull '${tag}' — the tag may have been renamed or the download interrupted."
      err "Check https://ollama.com/library and re-run this module."
      failed+=("$tag")
      continue
    fi

    # The pinned variant is the point of this module: it fixes num_ctx so a
    # large prompt is never silently truncated to the default.
    tmp="$(mktemp)"
    printf 'FROM %s\nPARAMETER num_ctx %s\nPARAMETER num_gpu 999\n' "$tag" "$ctx" >"$tmp"
    if ollama create "$variant" -f "$tmp" >/dev/null; then
      ok "${variant}: ${tag} pinned at num_ctx ${ctx}"
      installed+=("$variant")
    else
      err "Could not create the pinned variant '${variant}' for ${tag}."
      failed+=("$variant")
    fi
    rm -f "$tmp"
  done < <(_ollama_model_picks)

  # Opt-in: NVIDIA Nemotron 3 Nano. The Ollama-library tag is Q4_K_M (24GB)
  # and cannot fit a 24GB card; IQ4_XS (18.2GB) can, and only Unsloth
  # publishes it — so this path goes through Hugging Face.
  if [[ "${DEV_SETUP_OLLAMA_NEMOTRON:-0}" == "1" ]]; then
    _ollama_models_install_nemotron || failed+=("nemotron-3-nano")
  else
    log "Nemotron 3 Nano (best long-context evidence) not pulled — it needs a"
    log "Hugging Face GGUF. Re-run with DEV_SETUP_OLLAMA_NEMOTRON=1 to include it."
  fi

  if [[ ${#installed[@]} -gt 0 ]]; then
    log ""
    log "Use the pinned variants, not the bare tags:"
    for variant in "${installed[@]}"; do log "  ollama run ${variant}"; done
    log ""
    log "Verify each one loads fully on the GPU — 'ollama ps' must show 100% GPU."
    log "Any CPU split means the context is too large: lower num_ctx by 16K and rebuild."
    log "laguna-32k starts conservative; walk it up (49152, 65536) checking 'ollama ps' each time."
  fi

  if [[ ${#failed[@]} -gt 0 ]]; then
    err "Not everything succeeded: ${failed[*]}"
    return 1
  fi
}

_ollama_models_install_nemotron() {
  section "Nemotron 3 Nano 30B-A3B (IQ4_XS, via Hugging Face)"
  local hf=""
  if command_exists hf; then hf=hf
  elif command_exists huggingface-cli; then hf=huggingface-cli
  elif command_exists pipx; then
    log "Installing the Hugging Face CLI with pipx..."
    pipx install --quiet huggingface_hub[cli] >/dev/null 2>&1 || true
    command_exists hf && hf=hf
    command_exists huggingface-cli && hf=huggingface-cli
  fi
  if [[ -z "$hf" ]]; then
    warn "No Hugging Face CLI and no pipx to install one — skipping Nemotron."
    warn "Select the python module (which installs pipx and uv), then re-run."
    return 1
  fi

  local dir="${HOME}/models/nemotron3nano"
  mkdir -p "$dir"
  log "Downloading the IQ4_XS quant (~18GB). The Ollama-library tag is Q4_K_M"
  log "at 24GB, which cannot fit a 24GB card — this quant is why we use HF."
  "$hf" download unsloth/Nemotron-3-Nano-30B-A3B-GGUF \
    --include "*IQ4_XS*" --local-dir "$dir" \
    || { err "Hugging Face download failed."; return 1; }

  local gguf
  gguf="$(find "$dir" -name '*IQ4_XS*.gguf' -print -quit 2>/dev/null || true)"
  [[ -n "$gguf" ]] || { err "No IQ4_XS .gguf found under ${dir}."; return 1; }

  local tmp; tmp="$(mktemp)"
  printf 'FROM %s\nPARAMETER num_ctx 131072\nPARAMETER num_gpu 999\n' "$gguf" >"$tmp"
  if ollama create nemotron3nano-iq4xs -f "$tmp" >/dev/null; then
    ok "nemotron3nano-iq4xs: pinned at num_ctx 131072"
    log "Note: the model card warns that sub-4-bit quants degrade badly."
    log "IQ4_XS is the floor that fits 24GB, and quality at that floor is unmeasured."
  else
    rm -f "$tmp"; err "Could not import the Nemotron GGUF into Ollama."; return 1
  fi
  rm -f "$tmp"
}

module_ollama_models_uninstall() {
  section "Uninstall: Ollama coding models"
  sudo rm -f /etc/systemd/system/ollama.service.d/10-dev-setup-kv.conf
  sudo rmdir /etc/systemd/system/ollama.service.d 2>/dev/null || true
  sudo systemctl daemon-reload 2>/dev/null || true

  if ! command_exists ollama; then
    log "Ollama is already gone; nothing else to remove."
    return 0
  fi

  # Variants are cheap pointers at the base blobs — always remove those.
  local v
  for v in gptoss20b-128k gemma26b-128k laguna-32k nemotron3nano-iq4xs; do
    ollama rm "$v" >/dev/null 2>&1 && log "Removed variant: ${v}" || true
  done

  if [[ "${PURGE_DATA:-0}" == "1" ]]; then
    local t
    for t in gpt-oss:20b gemma4:26b-a4b-it-qat laguna-xs-2.1; do
      ollama rm "$t" >/dev/null 2>&1 && log "Removed model: ${t}" || true
    done
    rm -rf "${HOME}/models/nemotron3nano"
    log "Purged the downloaded model weights (~50GB)."
  else
    log "Kept: the downloaded weights (~50GB) — --purge-data removes them."
  fi
  sudo systemctl restart ollama 2>/dev/null || true
}
