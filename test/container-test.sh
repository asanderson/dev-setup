#!/usr/bin/env bash
# container-test.sh — run this repo's installer end-to-end in a fresh
# Ubuntu container and verify the installed tools.
#
# Usage:
#   ./test/container-test.sh [--rerun] [module ...]
#   ./test/container-test.sh --gpu-path
#
#   --rerun      run setup.sh a second time to verify idempotency
#   --gpu-path   instead of the module matrix, exercise the GPU-present
#                branches (docker module's NVIDIA Container Toolkit install,
#                nvidia runtime registration, ollama's GPU path) with an
#                nvidia-smi stub simulating the MSI Raider's RTX 5090. Runs
#                the container --privileged for the nested dockerd. Takes
#                no other arguments.
#   module ...   modules to test (default: git claude-code vscode docker
#                jdk maven cpp golang rust python). elastic and opensearch
#                (need a Docker daemon inside the container) and ollama
#                (GB-scale download, needs a GPU to be meaningful) are
#                excluded by default.
#
# Env:
#   DEV_SETUP_TEST_IMAGE   container image (default ubuntu:26.04)
#   https_proxy            forwarded into the container if set; a CA bundle
#                          at /root/.ccr/ca-bundle.crt is auto-mounted for
#                          CONNECT-only MITM proxies (sandbox/CI setups).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE="${DEV_SETUP_TEST_IMAGE:-ubuntu:26.04}"

RERUN=""
GPU_PATH=""
MODULES=()
for arg in "$@"; do
  case "$arg" in
    --rerun) RERUN="rerun" ;;
    --gpu-path) GPU_PATH="1" ;;
    *) MODULES+=("$arg") ;;
  esac
done

DOCKER_ARGS=(--rm --network host -v "${REPO_ROOT}:/repo:ro")
if [[ -n "${https_proxy:-}" ]]; then
  DOCKER_ARGS+=(-e https_proxy -e no_proxy)
  [[ -f /root/.ccr/ca-bundle.crt ]] && DOCKER_ARGS+=(-v /root/.ccr/ca-bundle.crt:/ccr-ca.crt:ro)
fi

if [[ -n "$GPU_PATH" ]]; then
  if [[ ${#MODULES[@]} -gt 0 || -n "$RERUN" ]]; then
    echo "error: --gpu-path takes no other arguments" >&2
    exit 2
  fi
  echo ">>> image: ${IMAGE}"
  echo ">>> GPU-path test (nvidia-smi stub; docker toolkit + ollama GPU branches)"
  exec docker run "${DOCKER_ARGS[@]}" --privileged "${IMAGE}" \
    bash /repo/test/gpu-path-init.sh
fi

[[ ${#MODULES[@]} -eq 0 ]] && MODULES=(git claude-code vscode docker jdk maven cpp golang rust python)

echo ">>> image: ${IMAGE}"
echo ">>> modules: ${MODULES[*]}${RERUN:+ (+ idempotency rerun)}"
docker run "${DOCKER_ARGS[@]}" "${IMAGE}" \
  bash /repo/test/container-init.sh "${MODULES[*]}" ${RERUN:+rerun}
