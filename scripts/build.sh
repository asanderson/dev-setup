#!/usr/bin/env bash
# build.sh — run the installer inside an image build and produce an
# OCI-compliant container image of the selected components.
#
#   Usage:              ./scripts/build.sh [--modules LIST] [--<component> ...]
#                                          [--tag NAME] [--engine docker|podman]
#   Unattended (all):   DEV_SETUP_ASSUME_YES=1 ./scripts/build.sh
#
# The image is Ubuntu 26.04 with the selected components installed by the
# same setup.sh modules, as user 'dev'. Excluded by design: docker and
# podman (they are the engines that RUN this image, not image content) and
# elastic/opensearch (their installs need a running Docker daemon — run
# those stacks beside the container instead). Run the result with
# scripts/run.sh.
#
# Corp/CONNECT proxies: https_proxy/no_proxy are passed through as build
# args, and DEV_SETUP_CA_BUNDLE=<path> injects a proxy CA into the build.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

IMAGE_MODULES=(git claude-code claude-plugins vscode jdk maven cpp golang rust python cloud
               proton-vpn proton-mail proton-bridge proton-drive proton-pass proton-meet proton-authenticator
               ollama)

usage() {
  echo "Usage: $0 [--modules LIST] [--<component> ...] [--tag NAME] [--engine docker|podman] [--list]"
  echo "  Builds an OCI image (default tag dev-setup:latest) of the selected"
  echo "  components; with no selection flags, all image-supported components:"
  echo "  ${IMAGE_MODULES[*]}"
  echo "  Not imageable: docker, podman (the engines), elastic, opensearch"
  echo "  (need a running daemon at install time)."
  echo "  --engine         docker (default) or podman"
  echo "  Component flags: $(printf -- '--%s ' "${IMAGE_MODULES[@]}")"
}

TAG="dev-setup:latest"
ENGINE="docker"
SELECTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --modules)
      IFS=, read -ra _mods <<<"${2:?--modules needs a comma-separated list}"
      SELECTED+=("${_mods[@]}")
      shift ;;
    --tag) TAG="${2:?--tag needs a name}"; shift ;;
    --engine)
      ENGINE="${2:?--engine needs docker or podman}"
      [[ "$ENGINE" == docker || "$ENGINE" == podman ]] \
        || { err "--engine must be docker or podman"; exit 2; }
      shift ;;
    --list) printf '%s\n' "${IMAGE_MODULES[@]}"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --*)
      _m="${1#--}"
      if [[ " ${IMAGE_MODULES[*]} " == *" ${_m} "* ]]; then
        SELECTED+=("$_m")
      else
        err "Unknown argument or non-imageable component: $1"; usage; exit 2
      fi ;;
    *) err "Unknown argument: $1"; usage; exit 2 ;;
  esac
  shift
done
for _m in ${SELECTED[@]+"${SELECTED[@]}"}; do
  [[ " ${IMAGE_MODULES[*]} " == *" ${_m} "* ]] \
    || { err "'${_m}' is not imageable (see --list)"; exit 2; }
done
[[ ${#SELECTED[@]} -eq 0 ]] && SELECTED=("${IMAGE_MODULES[@]}")

command_exists "$ENGINE" || die "${ENGINE} not found — install it (or pass the other --engine)."

MODLIST="$(IFS=,; echo "${SELECTED[*]}")"
log "Building ${TAG} with ${ENGINE}: ${MODLIST}"

# Optional proxy CA into the build context (removed from the image later).
CA_IN_CONTEXT=""
cleanup() { [[ -n "$CA_IN_CONTEXT" ]] && rm -f "$CA_IN_CONTEXT"; }
trap cleanup EXIT
if [[ -n "${DEV_SETUP_CA_BUNDLE:-}" && -f "${DEV_SETUP_CA_BUNDLE}" ]]; then
  CA_IN_CONTEXT="${REPO_ROOT}/.build-ca.crt"
  cp "${DEV_SETUP_CA_BUNDLE}" "$CA_IN_CONTEXT"
  log "Injecting proxy CA from ${DEV_SETUP_CA_BUNDLE} into the build."
fi

DOCKERFILE="$(mktemp)"
cat > "$DOCKERFILE" <<EOF
FROM ubuntu:26.04
ARG https_proxy
ARG no_proxy
ENV DEBIAN_FRONTEND=noninteractive
COPY . /opt/dev-setup
# Bootstrap mirrors test/container-init.sh: behind a CONNECT-only proxy the
# archives must be https and the proxy CA trusted before anything installs.
# The stock 'ubuntu' user is replaced by 'dev' AT uid 1000 — run.sh relies
# on uid 1000 owning /home/dev.
RUN if [ -n "\${https_proxy:-}" ]; then \\
      sed -i 's|http://\\(archive\\|security\\).ubuntu.com|https://\\1.ubuntu.com|g' /etc/apt/sources.list.d/ubuntu.sources; \\
      echo "Acquire::https::Proxy \"\${https_proxy}\";" >/etc/apt/apt.conf.d/95proxy; \\
      if [ -f /opt/dev-setup/.build-ca.crt ]; then echo 'Acquire::https::CAInfo "/opt/dev-setup/.build-ca.crt";' >>/etc/apt/apt.conf.d/95proxy; fi; \\
    fi \\
 && apt-get update -qq \\
 && apt-get install -y -qq sudo ca-certificates curl gnupg openssl >/dev/null \\
 && if [ -f /opt/dev-setup/.build-ca.crt ]; then \\
      cp /opt/dev-setup/.build-ca.crt /usr/local/share/ca-certificates/build-ca.crt \\
      && update-ca-certificates >/dev/null; \\
    fi \\
 && { userdel -r ubuntu 2>/dev/null || true; } \\
 && useradd -m -u 1000 -s /bin/bash dev \\
 && echo 'dev ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dev \\
 && chmod 440 /etc/sudoers.d/dev \\
 && echo 'Defaults env_keep += "https_proxy no_proxy DEBIAN_FRONTEND"' >/etc/sudoers.d/proxy-env \\
 && chmod 440 /etc/sudoers.d/proxy-env \\
 && chown -R dev:dev /opt/dev-setup
USER dev
RUN cd /opt/dev-setup \\
 && DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh --os ubuntu --modules ${MODLIST}
USER root
RUN rm -f /opt/dev-setup/.build-ca.crt /etc/apt/apt.conf.d/95proxy
USER dev
WORKDIR /home/dev
LABEL org.opencontainers.image.title="dev-setup" \\
      org.opencontainers.image.description="dev-setup components: ${MODLIST}" \\
      org.opencontainers.image.source="https://github.com/asanderson/dev-setup"
CMD ["/bin/bash", "-l"]
EOF

# Extra engine-build options for unusual environments — e.g. a daemon
# running with --bridge=none needs DEV_SETUP_BUILD_OPTS="--network host".
read -ra EXTRA_BUILD_OPTS <<<"${DEV_SETUP_BUILD_OPTS:-}"

"$ENGINE" build \
  ${https_proxy:+--build-arg https_proxy --build-arg no_proxy} \
  ${EXTRA_BUILD_OPTS[@]+"${EXTRA_BUILD_OPTS[@]}"} \
  -f "$DOCKERFILE" -t "$TAG" "$REPO_ROOT"
rm -f "$DOCKERFILE"

ok "Image built: ${TAG} (components: ${MODLIST})"
log "Run it: ./scripts/run.sh --image ${TAG}  (docker default; --engine podman)"
