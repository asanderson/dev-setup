#!/usr/bin/env bash
# engines-test.sh — install the container-engine modules (docker, podman)
# in a fresh container of ONE target OS and verify them, per the support
# matrix: docker everywhere Docker has an official repo path (ubuntu,
# debian, rocky via Docker's centos repo, rhel), podman on all five
# targets including pureos.
#
# Usage: ./test/engines-test.sh <ubuntu|debian|pureos|rocky|rhel>
#
# Images are the official/vendor base image per OS. PureOS note: Purism
# publishes OCI images only for byzantium (PureOS 10) — the installer's
# target check needs ID=pureos from /etc/os-release, which that image has.
#
# Env:
#   DEV_SETUP_TEST_IMAGE   override the container image
#   https_proxy            forwarded into the container if set; a CA bundle
#                          at /root/.ccr/ca-bundle.crt is auto-mounted for
#                          CONNECT-only MITM proxies (sandbox/CI setups).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OS="${1:?usage: engines-test.sh <ubuntu|debian|pureos|rocky|rhel>}"
case "$OS" in
  ubuntu) IMAGE="ubuntu:26.04";                        MODULES="docker podman" ;;
  debian) IMAGE="debian:13";                           MODULES="docker podman" ;;
  pureos) IMAGE="pureos/byzantium";                    MODULES="podman" ;;
  rocky)  IMAGE="rockylinux:9";                        MODULES="docker podman" ;;
  rhel)   IMAGE="registry.access.redhat.com/ubi9/ubi"; MODULES="docker podman" ;;
  *) echo "error: unknown target OS '$OS' (ubuntu|debian|pureos|rocky|rhel)" >&2; exit 2 ;;
esac
IMAGE="${DEV_SETUP_TEST_IMAGE:-$IMAGE}"

DOCKER_ARGS=(--rm --network host -v "${REPO_ROOT}:/repo:ro")
if [[ -n "${https_proxy:-}" ]]; then
  DOCKER_ARGS+=(-e https_proxy -e no_proxy)
fi
# CA mount is independent of the proxy env: a transparently-intercepting
# proxy MITMs outbound TLS with no proxy variable set at all.
if [[ -f /root/.ccr/ca-bundle.crt ]]; then
  DOCKER_ARGS+=(-v /root/.ccr/ca-bundle.crt:/ccr-ca.crt:ro)
fi

echo ">>> target OS: ${OS}  image: ${IMAGE}"
echo ">>> engine modules: ${MODULES}"
exec docker run "${DOCKER_ARGS[@]}" "${IMAGE}" \
  bash /repo/test/engines-init.sh "$OS" "$MODULES"
