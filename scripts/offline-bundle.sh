#!/usr/bin/env bash
# offline-bundle.sh — package everything the selected components need into a
# single archive for a SELF-CONTAINED OFFLINE INSTALL in an air-gapped
# enclave (Ubuntu 26.04 amd64 targets).
#
# The SBOM (sbom.cdx.json) is the authoritative component manifest: pinned
# versions are taken from it (via config/versions.env), latest-resolved
# components are resolved once at PACK time and recorded in the bundle's
# MANIFEST.sha256. The apt dependency closure is computed inside a FRESH
# Ubuntu 26.04 container, so the bundle is complete for a clean enclave
# machine regardless of what the packing host has installed.
#
# Usage (on a connected machine with Docker):
#   ./scripts/offline-bundle.sh --pack [--modules LIST] [--out DIR]
#
# Result: dev-setup-offline-<date>.tar.gz containing debs/, artifacts/,
# images/, vsix/, config/, sbom.cdx.json, MANIFEST.sha256, and a standalone
# install-offline.sh (see scripts/lib/install-offline.sh) that needs neither
# this repo nor a network. Unpack in the enclave and run it.
#
# Offline-packagable components: git vscode docker podman jdk maven cpp
# golang rust python cloud elastic opensearch ollama. Excluded by design:
# claude-code and claude-plugins (the CLI is a network service — it cannot
# log in or reach the API from an enclave) and the proton-* apps (network
# services). git is packaged from the Ubuntu archive (no PPA offline).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../config/versions.env
source "${REPO_ROOT}/config/versions.env"

OFFLINE_MODULES=(git vscode docker podman jdk maven cpp golang rust python cloud elastic opensearch ollama)

usage() {
  echo "Usage: $0 --pack [--modules LIST] [--out DIR]"
  echo "  --pack           build the offline bundle (requires network + Docker)"
  echo "  --modules LIST   comma-separated subset (default: all offline-packagable:"
  echo "                   ${OFFLINE_MODULES[*]})"
  echo "  --out DIR        output directory (default: current directory)"
  echo "  Not packagable (network services): claude-code claude-plugins proton-*"
  echo "  Not yet packaged: nodejs (NodeSource repo + Bun artifact support pending)"
  echo "  Not packagable: ollama-models (~50GB of weights; copy the Ollama"
  echo "                 model store across separately if you need them offline)"
}

MODE=""
OUT_DIR="$PWD"
SELECTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pack) MODE=pack ;;
    --modules)
      IFS=, read -ra SELECTED <<<"${2:?--modules needs a comma-separated list}"
      shift ;;
    --out) OUT_DIR="${2:?--out needs a directory}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown argument: $1"; usage; exit 2 ;;
  esac
  shift
done
[[ "$MODE" == "pack" ]] || { usage; exit 2; }
[[ ${#SELECTED[@]} -eq 0 ]] && SELECTED=("${OFFLINE_MODULES[@]}")
for m in "${SELECTED[@]}"; do
  [[ " ${OFFLINE_MODULES[*]} " == *" $m "* ]] \
    || die "'$m' is not offline-packagable (choose from: ${OFFLINE_MODULES[*]})"
done

command_exists docker || die "Packing needs Docker (fresh-container apt resolution + image saves)."
command_exists jq || die "Packing needs jq (SBOM parsing)."
[[ -f "${REPO_ROOT}/sbom.cdx.json" ]] || die "sbom.cdx.json not found — pack from a repo checkout."

STAMP="$(date +%Y%m%d)"
BUNDLE="dev-setup-offline-${STAMP}"
WORK="${OUT_DIR}/${BUNDLE}"
mkdir -p "$WORK"/{debs,artifacts,images,vsix,config}

log "Packing modules: ${SELECTED[*]}"
log "Bundle: ${WORK}"

sel() { [[ " ${SELECTED[*]} " == *" $1 "* ]]; }

# ---- apt dependency closure (fresh Ubuntu 26.04 container) -----------------
# Vendor repos are enabled per selected module, mirroring the modules'
# sources (docker, apt.llvm.org, packages.microsoft.com); the closure comes
# from `apt-get install --download-only` on a clean system.
declare -A APT_PKGS=(
  [base]="curl ca-certificates gnupg lsb-release openssl unzip jq zstd"
  [git]="git git-lfs"
  [vscode]="code"
  [docker]="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
  [podman]="podman uidmap"
  [jdk]="openjdk-25-jdk"
  [cpp]="build-essential gcc g++ gdb clang clangd clang-format clang-tidy lldb llvm cmake ninja-build ccache valgrind pkg-config autoconf automake libtool manpages-dev clang-${LLVM_VERSION} clangd-${LLVM_VERSION} clang-format-${LLVM_VERSION} clang-tidy-${LLVM_VERSION} lld-${LLVM_VERSION} lldb-${LLVM_VERSION} llvm-${LLVM_VERSION}"
  [python]="python3 python3-venv python3-pip python3-dev pipx"
  [cloud]="unzip"
)
apt_list="${APT_PKGS[base]}"
enable_docker_repo=0 enable_llvm_repo=0 enable_ms_repo=0
for m in "${SELECTED[@]}"; do
  apt_list+=" ${APT_PKGS[$m]:-}"
  [[ "$m" == docker ]] && enable_docker_repo=1
  [[ "$m" == cpp ]] && enable_llvm_repo=1
  [[ "$m" == vscode ]] && enable_ms_repo=1
done

# Optional CONNECT-proxy CA mount (sandbox/CI packing hosts).
CA_ARGS=()
[[ -f /root/.ccr/ca-bundle.crt ]] && CA_ARGS=(-v /root/.ccr/ca-bundle.crt:/ccr-ca.crt:ro)

# Vendor repo keys are fetched HERE on the host (armored — apt accepts
# armored files at Signed-By paths), so the resolver container stays nearly
# pristine and the dependency closure isn't hidden by bootstrap installs.
KEYS_DIR="$(mktemp -d)"
trap 'rm -rf "$KEYS_DIR"' EXIT
[[ "$enable_docker_repo" == 1 ]] && fetch https://download.docker.com/linux/ubuntu/gpg -o "${KEYS_DIR}/docker.asc"
[[ "$enable_llvm_repo" == 1 ]] && fetch https://apt.llvm.org/llvm-snapshot.gpg.key -o "${KEYS_DIR}/llvm.asc"
[[ "$enable_ms_repo" == 1 ]] && fetch https://packages.microsoft.com/keys/microsoft.asc -o "${KEYS_DIR}/microsoft.asc"

section "apt dependency closure (fresh ubuntu:26.04 container)"
# -i: the fetch script arrives on stdin (heredoc below).
docker run --rm -i --network host \
  -v "${WORK}/debs:/out" \
  -v "${KEYS_DIR}:/aptkeys:ro" \
  ${https_proxy:+-e https_proxy -e no_proxy} \
  ${CA_ARGS[@]+"${CA_ARGS[@]}"} \
  -e ENABLE_DOCKER_REPO="$enable_docker_repo" \
  -e ENABLE_LLVM_REPO="$enable_llvm_repo" \
  -e ENABLE_MS_REPO="$enable_ms_repo" \
  -e LLVM_VERSION="$LLVM_VERSION" \
  -e APT_LIST="$apt_list" \
  ubuntu:26.04 bash -s <<'INNER'
set -euo pipefail
unset http_proxy HTTP_PROXY
if [[ -n "${https_proxy:-}" ]]; then
  sed -i 's|http://\(archive\|security\).ubuntu.com|https://\1.ubuntu.com|g' \
    /etc/apt/sources.list.d/ubuntu.sources
  { echo "Acquire::https::Proxy \"${https_proxy}\";"
    [[ -f /ccr-ca.crt ]] && echo 'Acquire::https::CAInfo "/ccr-ca.crt";'
  } >/etc/apt/apt.conf.d/95proxy
fi
export DEBIAN_FRONTEND=noninteractive
# Snapshot the pristine package state: anything installed after this point
# (the TLS bootstrap and its deps) is exactly what --download-only would
# silently skip — it gets flat-downloaded at the end so the bundle repo is
# complete for a stock target.
dpkg-query -W -f '${binary:Package}\n' | sort > /tmp/pkgs.before
apt-get update -qq
apt-get install -y -qq ca-certificates >/dev/null
[[ -f /ccr-ca.crt ]] && { cp /ccr-ca.crt /usr/local/share/ca-certificates/p.crt; update-ca-certificates >/dev/null 2>&1; }
. /etc/os-release
install -m 0755 -d /etc/apt/keyrings
cp /aptkeys/*.asc /etc/apt/keyrings/ 2>/dev/null || true
if [[ "$ENABLE_DOCKER_REPO" == 1 ]]; then
  printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
    "${UBUNTU_CODENAME:-$VERSION_CODENAME}" >/etc/apt/sources.list.d/docker.sources
fi
if [[ "$ENABLE_LLVM_REPO" == 1 ]]; then
  echo "deb [signed-by=/etc/apt/keyrings/llvm.asc] https://apt.llvm.org/${VERSION_CODENAME}/ llvm-toolchain-${VERSION_CODENAME}-${LLVM_VERSION} main" \
    >/etc/apt/sources.list.d/llvm.list
fi
if [[ "$ENABLE_MS_REPO" == 1 ]]; then
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.asc] https://packages.microsoft.com/repos/code stable main" \
    >/etc/apt/sources.list.d/vscode.list
fi
apt-get update -qq
# shellcheck disable=SC2086
apt-get install -y --download-only -o Dir::Cache::archives=/out $APT_LIST
# Flat-download the bootstrap diff (see snapshot above).
dpkg-query -W -f '${binary:Package}\n' | sort > /tmp/pkgs.after
boot_diff="$(comm -13 /tmp/pkgs.before /tmp/pkgs.after | tr '\n' ' ')"
if [[ -n "${boot_diff// }" ]]; then
  # shellcheck disable=SC2086
  ( cd /out && apt-get download $boot_diff )
fi
# Index the download as a local apt repo, so the offline installer can let
# apt resolve ordering from a file: source instead of raw dpkg ordering.
# (dpkg-dev is index tooling only — installed after the diff, never shipped.)
apt-get install -y -qq dpkg-dev >/dev/null
( cd /out && dpkg-scanpackages --multiversion . /dev/null 2>/dev/null | gzip > Packages.gz )
# shellcheck disable=SC2086
printf '%s\n' $APT_LIST | sort -u > /out/PACKAGES.list
chmod -R a+r /out
echo "debs: $(ls /out/*.deb | wc -l) (incl. bootstrap diff: ${boot_diff:-none})"
INNER

# ---- direct artifacts ------------------------------------------------------
section "Vendor artifacts"
art() { mkdir -p "${WORK}/artifacts/$1"; }

if sel maven; then
  art maven
  log "Maven ${MAVEN_VERSION} (SBOM pin)"
  fetch "https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    -o "${WORK}/artifacts/maven/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    || fetch "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
         -o "${WORK}/artifacts/maven/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
fi

if sel golang; then
  art go
  gover="$(fetch 'https://go.dev/VERSION?m=text' | head -n1)"
  log "Go ${gover} (resolved at pack time)"
  fetch "https://go.dev/dl/${gover}.linux-amd64.tar.gz" -o "${WORK}/artifacts/go/${gover}.linux-amd64.tar.gz"
fi

if sel rust; then
  art rust
  rustver="$(fetch https://static.rust-lang.org/dist/channel-rust-stable.toml \
    | grep -A2 '^\[pkg.rust\]' | grep '^version' | sed 's/.*"\([0-9.]*\).*/\1/')"
  log "Rust ${rustver} standalone offline installer (resolved at pack time)"
  fetch "https://static.rust-lang.org/dist/rust-${rustver}-x86_64-unknown-linux-gnu.tar.xz" \
    -o "${WORK}/artifacts/rust/rust-${rustver}-x86_64-unknown-linux-gnu.tar.xz"
fi

if sel cloud; then
  art k3s; art helm; art k9s; art aws
  log "k3s (latest release + air-gap images, per the documented air-gap procedure)"
  fetch "https://github.com/k3s-io/k3s/releases/latest/download/k3s" -o "${WORK}/artifacts/k3s/k3s"
  fetch "https://github.com/k3s-io/k3s/releases/latest/download/k3s-airgap-images-amd64.tar.zst" \
    -o "${WORK}/artifacts/k3s/k3s-airgap-images-amd64.tar.zst"
  fetch "https://get.k3s.io" -o "${WORK}/artifacts/k3s/install.sh"
  helmtag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/helm/helm/releases/latest | sed 's|.*/||')"
  log "Helm ${helmtag} (resolved at pack time)"
  fetch "https://get.helm.sh/helm-${helmtag}-linux-amd64.tar.gz" \
    -o "${WORK}/artifacts/helm/helm-${helmtag}-linux-amd64.tar.gz"
  k9sver="$(fetch https://api.github.com/repos/derailed/k9s/releases/latest 2>/dev/null \
    | grep -o '"tag_name": *"[^"]*"' | head -n1 | sed 's/.*"\(v[^"]*\)"/\1/')" || true
  [[ -n "$k9sver" ]] || k9sver="$K9S_VERSION"
  log "k9s ${k9sver}"
  fetch "https://github.com/derailed/k9s/releases/download/${k9sver}/k9s_linux_amd64.deb" \
    -o "${WORK}/artifacts/k9s/k9s_linux_amd64.deb"
  log "AWS CLI v2 (latest bundle)"
  fetch "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "${WORK}/artifacts/aws/awscliv2.zip"
  log "Ansible: packaged as a pip wheel set for offline pipx install"
  art ansible
  PIP_CA_ARGS=()
  [[ -f /root/.ccr/ca-bundle.crt ]] && PIP_CA_ARGS=(-v /root/.ccr/ca-bundle.crt:/ccr-ca.crt:ro -e PIP_CERT=/ccr-ca.crt)
  docker run --rm --network host -v "${WORK}/artifacts/ansible:/out" \
    ${https_proxy:+-e https_proxy -e no_proxy} \
    ${PIP_CA_ARGS[@]+"${PIP_CA_ARGS[@]}"} \
    ubuntu:26.04 bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq python3-pip >/dev/null && pip download --no-cache-dir -d /out ansible 2>&1 | tail -1 && chmod -R a+r /out'
fi

if sel ollama; then
  art ollama
  log "Ollama standalone bundle (latest; the documented manual-install artifact)"
  fetch "https://ollama.com/download/ollama-linux-amd64.tgz" -o "${WORK}/artifacts/ollama/ollama-linux-amd64.tgz"
fi

# ---- container images ------------------------------------------------------
if sel elastic || sel opensearch; then
  section "Container images (docker pull + save)"
  imgs=()
  sel elastic && imgs+=("docker.elastic.co/elasticsearch/elasticsearch:${ELASTIC_VERSION}" "docker.elastic.co/kibana/kibana:${ELASTIC_VERSION}")
  sel opensearch && imgs+=("opensearchproject/opensearch:${OPENSEARCH_VERSION}" "opensearchproject/opensearch-dashboards:${OPENSEARCH_VERSION}")
  for img in "${imgs[@]}"; do
    log "Pulling ${img}"
    docker pull -q "$img"
  done
  docker save "${imgs[@]}" | gzip > "${WORK}/images/stack-images.tar.gz"
  sel elastic && cp -r "${REPO_ROOT}/config/elastic" "${WORK}/config/"
  sel opensearch && cp -r "${REPO_ROOT}/config/opensearch" "${WORK}/config/"
  # Record the exact packed image versions for the offline installer's .env.
  { sel elastic && echo "ELASTIC_VERSION=${ELASTIC_VERSION}"
    sel opensearch && echo "OPENSEARCH_VERSION=${OPENSEARCH_VERSION}"
  } > "${WORK}/config/stack-versions.env" || true
fi

# ---- VS Code extensions ----------------------------------------------------
if sel vscode; then
  section "VS Code extensions (.vsix, newest marketplace version)"
  mapfile -t EXT_IDS < <(jq -r '.components[] | select(.externalReferences[]?.url | strings | contains("marketplace.visualstudio.com")) | .name' "${REPO_ROOT}/sbom.cdx.json")
  log "Extensions from the SBOM: ${#EXT_IDS[@]}"
  for id in "${EXT_IDS[@]}"; do
    pub="${id%%.*}"; name="${id#*.}"
    fetch --compressed \
      "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${pub}/vsextensions/${name}/latest/vspackage" \
      -o "${WORK}/vsix/${id}.vsix" || warn "  ${id}: download failed (install online later)"
  done
fi

# ---- provenance, installer, manifest, archive ------------------------------
section "Finalize"
cp "${REPO_ROOT}/sbom.cdx.json" "${WORK}/"
cp "${SCRIPT_DIR}/lib/install-offline.sh" "${WORK}/install-offline.sh"
chmod +x "${WORK}/install-offline.sh"
printf '%s\n' "${SELECTED[@]}" > "${WORK}/MODULES"
( cd "$WORK" && find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256 )
tar -C "$OUT_DIR" -czf "${OUT_DIR}/${BUNDLE}.tar.gz" "$BUNDLE"
rm -rf "$WORK"
ok "Bundle: ${OUT_DIR}/${BUNDLE}.tar.gz ($(du -h "${OUT_DIR}/${BUNDLE}.tar.gz" | cut -f1))"
log "Enclave install: untar, then ./${BUNDLE}/install-offline.sh (Ubuntu 26.04 amd64; no network needed)."
