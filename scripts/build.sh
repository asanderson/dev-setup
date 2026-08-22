#!/usr/bin/env bash
# build.sh — run the installer inside an image build and produce an
# OCI-compliant container image of the selected components, for any
# target OS in the catalog.
#
#   Usage:              ./scripts/build.sh [--os TARGET] [--modules LIST]
#                                          [--<component> ...] [--tag NAME]
#                                          [--engine docker|podman]
#   Unattended (all):   DEV_SETUP_ASSUME_YES=1 ./scripts/build.sh
#
# The image is the target OS's base image (Ubuntu 26.04 by default) with
# the selected components installed by the same setup.sh modules, as user
# 'dev' (uid 1000). Excluded by design: docker and podman (they are the
# engines that RUN this image, not image content), elastic/opensearch
# (their installs need a running Docker daemon — run those stacks beside
# the container instead), proton-vpn (its daemon's postinst needs a
# running systemd, and a VPN belongs on the host anyway), and
# ollama-models (~50GB of GPU-bound weights; pull them on the host). Run
# the result with scripts/run.sh.
#
# PureOS note: Purism publishes OCI images only for byzantium (PureOS 10),
# so --os pureos builds on that base.
#
# Images never run systemd, so a no-op systemctl stub stands in during the
# build (module service-enable steps are meaningless in an image) and is
# removed from the final image.
#
# Corp/CONNECT proxies: https_proxy/no_proxy are passed through as build
# args, DEV_SETUP_CA_BUNDLE=<path> injects a proxy CA into the build, and
# DEV_SETUP_BUILD_OPTS passes extra engine-build options (e.g.
# "--network host" for a daemon running with --bridge=none).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

IMAGE_MODULES=(git nodejs claude-code claude-plugins vscode jdk maven cpp golang rust python cloud
               proton-mail proton-bridge proton-drive proton-pass proton-meet proton-authenticator
               ollama)

# Base image per target OS (matching test/engines-test.sh).
declare -A OS_BASE=(
  [ubuntu]="ubuntu:26.04"
  [debian]="debian:13"
  [pureos]="pureos/byzantium"
  [rocky]="rockylinux:9"
  [rhel]="registry.access.redhat.com/ubi9/ubi"
)

usage() {
  echo "Usage: $0 [--os TARGET] [--modules LIST] [--<component> ...] [--tag NAME] [--engine docker|podman] [--list]"
  echo "  Builds an OCI image (default tag dev-setup:latest) of the selected"
  echo "  components; with no selection flags, all image-supported components:"
  echo "  ${IMAGE_MODULES[*]}"
  echo "  Not imageable: docker, podman (the engines), elastic, opensearch"
  echo "  (need a running daemon at install time), proton-vpn (daemon needs"
  echo "  running systemd), ollama-models (~50GB of weights that need a GPU"
  echo "  and a running Ollama daemon — pull them on the host)."
  echo "  --os             target OS: ${!OS_BASE[*]} (default ubuntu)"
  echo "  --engine         docker (default) or podman"
  echo "  Component flags: $(printf -- '--%s ' "${IMAGE_MODULES[@]}")"
}

TAG="dev-setup:latest"
ENGINE="docker"
TARGET_OS="ubuntu"
SELECTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --os)
      TARGET_OS="${2:?--os needs a target OS}"
      [[ -n "${OS_BASE[$TARGET_OS]:-}" ]] \
        || { err "--os must be one of: ${!OS_BASE[*]}"; exit 2; }
      shift ;;
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

# Per-OS exclusions from the default set, with the reasons:
# - proton-authenticator needs libwebkit2gtk-4.1 — absent from EL9's repos
#   (rocky/rhel) and from the byzantium base PureOS builds on (real PureOS
#   crimson has it, but Purism publishes no crimson OCI image).
# - The rhel base is Red Hat's UBI, whose unentitled repos carry no GUI
#   stacks: vscode and the Proton desktop apps need libraries (xdg-utils,
#   libnotify, libxkbcommon-x11, ...) only a subscribed RHEL host has —
#   install those with setup.sh on the real machine instead.
declare -A OS_IMAGE_EXCLUDE=(
  [rocky]="proton-authenticator"
  [rhel]="proton-authenticator vscode proton-mail proton-bridge proton-pass proton-meet"
  [pureos]="proton-authenticator"
)
EXCLUDED="${OS_IMAGE_EXCLUDE[$TARGET_OS]:-}"
for _m in ${SELECTED[@]+"${SELECTED[@]}"}; do
  if [[ " ${EXCLUDED} " == *" ${_m} "* ]]; then
    err "'${_m}' cannot be imaged on ${TARGET_OS} (see the exclusion notes in this script)."
    exit 2
  fi
done
if [[ ${#SELECTED[@]} -eq 0 ]]; then
  for _m in "${IMAGE_MODULES[@]}"; do
    [[ " ${EXCLUDED} " == *" ${_m} "* ]] || SELECTED+=("$_m")
  done
  if [[ -n "$EXCLUDED" ]]; then log "Excluded on ${TARGET_OS}: ${EXCLUDED}"; fi
fi

command_exists "$ENGINE" || die "${ENGINE} not found — install it (or pass the other --engine)."

BASE_IMAGE="${OS_BASE[$TARGET_OS]}"
FAMILY=deb
[[ "$TARGET_OS" == rocky || "$TARGET_OS" == rhel ]] && FAMILY=rpm
MODLIST="$(IFS=,; echo "${SELECTED[*]}")"
log "Building ${TAG} with ${ENGINE}: --os ${TARGET_OS} (${BASE_IMAGE}), modules: ${MODLIST}"

# Optional proxy CA into the build context (removed from the image later).
# The filename is unique per invocation: concurrent builds share the repo
# root, and one build's exit-trap cleanup must not delete another's CA
# before its context transfer snapshots it.
CA_BASENAME=".build-ca.$$.crt"
CA_IN_CONTEXT=""
# if-form, not `[[ ]] &&`: a false guard as the trap's last command would
# override the script's exit status with 1 under set -e.
cleanup() { if [[ -n "$CA_IN_CONTEXT" ]]; then rm -f "$CA_IN_CONTEXT"; fi; }
trap cleanup EXIT
if [[ -n "${DEV_SETUP_CA_BUNDLE:-}" && -f "${DEV_SETUP_CA_BUNDLE}" ]]; then
  CA_IN_CONTEXT="${REPO_ROOT}/${CA_BASENAME}"
  cp "${DEV_SETUP_CA_BUNDLE}" "$CA_IN_CONTEXT"
  log "Injecting proxy CA from ${DEV_SETUP_CA_BUNDLE} into the build."
fi

DOCKERFILE="$(mktemp)"

# --- family-specific bootstrap (proxy plumbing + base packages + CA) -----
if [[ "$FAMILY" == deb ]]; then
  BOOTSTRAP=$(cat <<'EOS'
RUN if [ -n "${https_proxy:-}" ]; then \
      sed -i 's|http://|https://|g' /etc/apt/sources.list 2>/dev/null || true; \
      sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.sources 2>/dev/null || true; \
      sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.list 2>/dev/null || true; \
      echo "Acquire::https::Proxy \"${https_proxy}\";" >/etc/apt/apt.conf.d/95proxy; \
      if [ -f /opt/dev-setup/.build-ca.crt ]; then echo 'Acquire::https::CAInfo "/opt/dev-setup/.build-ca.crt";' >>/etc/apt/apt.conf.d/95proxy; fi; \
    fi \
 && apt-get update -qq \
 && apt-get install -y -qq sudo ca-certificates curl gnupg openssl >/dev/null \
 && if [ -f /opt/dev-setup/.build-ca.crt ]; then \
      cp /opt/dev-setup/.build-ca.crt /usr/local/share/ca-certificates/build-ca.crt \
      && update-ca-certificates >/dev/null; \
    fi
EOS
)
  PROXY_CLEANUP="rm -f /etc/apt/apt.conf.d/95proxy"
else
  BOOTSTRAP=$(cat <<'EOS'
# CA trust first and unconditionally: a transparently-intercepting proxy
# MITMs dnf's https mirrorlists with no proxy env var set at all.
RUN if [ -f /opt/dev-setup/.build-ca.crt ]; then \
      cp /opt/dev-setup/.build-ca.crt /etc/pki/ca-trust/source/anchors/build-ca.crt \
      && update-ca-trust; \
    fi \
 && if [ -n "${https_proxy:-}" ]; then \
      echo "proxy=${https_proxy}" >>/etc/dnf/dnf.conf; \
      sed -i -e 's|^mirrorlist=|#mirrorlist=|' -e 's|^#baseurl=http://|baseurl=https://|' /etc/yum.repos.d/*.repo 2>/dev/null || true; \
    fi \
 && dnf install -y sudo shadow-utils ca-certificates >/dev/null
EOS
)
  PROXY_CLEANUP="sed -i '/^proxy=/d' /etc/dnf/dnf.conf"
fi
# Point the generated bootstrap at this invocation's CA filename.
BOOTSTRAP="${BOOTSTRAP//.build-ca.crt/${CA_BASENAME}}"

cat > "$DOCKERFILE" <<EOF
FROM ${BASE_IMAGE}
ARG https_proxy
ARG no_proxy
ENV DEBIAN_FRONTEND=noninteractive
COPY . /opt/dev-setup
# Bootstrap mirrors the test harness (test/engines-init.sh): proxy plumbing
# first where a CONNECT-only proxy carries the build, then base packages.
# The user 'dev' is created AT uid 1000 — run.sh relies on uid 1000 owning
# /home/dev — evicting any stock user the base image parks there (ubuntu's
# base ships one). Images never run systemd: a no-op systemctl stub stands
# in for the modules' service steps and is removed from the final image;
# the sudoers secure_path keeps the stub visible under sudo on EL.
${BOOTSTRAP}
RUN _stock="\$(getent passwd 1000 | cut -d: -f1)" \\
 && if [ -n "\$_stock" ]; then userdel -r "\$_stock" 2>/dev/null || true; fi \\
 && useradd -m -u 1000 -s /bin/bash dev \\
 && echo 'dev ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dev \\
 && echo 'Defaults env_keep += "https_proxy no_proxy DEBIAN_FRONTEND"' >/etc/sudoers.d/proxy-env \\
 && echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >/etc/sudoers.d/secure-path \\
 && chmod 440 /etc/sudoers.d/dev /etc/sudoers.d/proxy-env /etc/sudoers.d/secure-path \\
 && printf '#!/bin/sh\\necho "systemctl (image build stub): ignoring: \$*"\\nexit 0\\n' >/usr/local/bin/systemctl \\
 && chmod +x /usr/local/bin/systemctl \\
 && chown -R dev:dev /opt/dev-setup
USER dev
# NODE_EXTRA_CA_CERTS: Node-based tools (the code CLI's marketplace
# client) ignore the system trust store, so hand them the injected CA
# directly. No-op when no CA was injected.
RUN cd /opt/dev-setup \\
 && if [ -f /opt/dev-setup/${CA_BASENAME} ]; then export NODE_EXTRA_CA_CERTS=/opt/dev-setup/${CA_BASENAME}; fi \\
 && DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh --os ${TARGET_OS} --modules ${MODLIST}
USER root
RUN rm -f /opt/dev-setup/${CA_BASENAME} /usr/local/bin/systemctl /etc/sudoers.d/secure-path \\
 && ${PROXY_CLEANUP}
USER dev
WORKDIR /home/dev
LABEL org.opencontainers.image.title="dev-setup (${TARGET_OS})" \\
      org.opencontainers.image.description="dev-setup ${TARGET_OS} components: ${MODLIST}" \\
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

ok "Image built: ${TAG} (--os ${TARGET_OS}, components: ${MODLIST})"
log "Run it: ./scripts/run.sh --image ${TAG}  (docker default; --engine podman)"
