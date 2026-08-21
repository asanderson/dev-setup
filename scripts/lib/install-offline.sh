#!/usr/bin/env bash
# install-offline.sh — SELF-CONTAINED offline installer, shipped inside the
# bundle built by scripts/offline-bundle.sh. Runs in an air-gapped enclave
# on Ubuntu 26.04 amd64 with NO network and NO repo checkout: everything it
# installs comes from the files beside it. Installs whatever the bundle
# contains (module selection happened at pack time — see ./MODULES).
#
# Run as a regular user with sudo, or as root.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log()  { printf '[offline] %s\n' "$*"; }
warn() { printf '[offline][warn] %s\n' "$*" >&2; }
die()  { printf '[offline][fail] %s\n' "$*" >&2; exit 1; }

SUDO="sudo"
[[ "$(id -u)" -eq 0 ]] && SUDO=""

[[ -f "${HERE}/MANIFEST.sha256" ]] || die "MANIFEST.sha256 missing — is this an intact bundle?"
log "Verifying bundle integrity (MANIFEST.sha256)..."
( cd "$HERE" && sha256sum --quiet -c MANIFEST.sha256 ) || die "Checksum mismatch — the bundle is corrupt or was modified."
log "Bundle intact. Modules packed: $(tr '\n' ' ' < "${HERE}/MODULES")"

# ---- debs (complete dependency closure from pack time) ---------------------
# The bundle is a local apt repo (Packages.gz generated at pack time): apt
# resolves install ordering itself from the file: source — no network, and
# no raw-dpkg ordering problems on large sets.
if compgen -G "${HERE}/debs/*.deb" >/dev/null; then
  log "Installing $(ls "${HERE}"/debs/*.deb | wc -l) packages from the bundled local apt repo..."
  list=/etc/apt/sources.list.d/dev-setup-offline.list
  echo "deb [trusted=yes] file:${HERE}/debs ./" | $SUDO tee "$list" >/dev/null
  # Update ONLY our source — the machine's normal sources are unreachable here.
  $SUDO apt-get update -qq \
    -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts=/dev/null
  # shellcheck disable=SC2046  # package names are safe single tokens
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    $(cat "${HERE}/debs/PACKAGES.list")
  $SUDO rm -f "$list"
  log "Packages installed."
fi

# ---- Maven -----------------------------------------------------------------
if compgen -G "${HERE}/artifacts/maven/apache-maven-*.tar.gz" >/dev/null; then
  tarball="$(compgen -G "${HERE}/artifacts/maven/apache-maven-*.tar.gz" | head -n1)"
  ver="$(basename "$tarball" | sed 's/apache-maven-\(.*\)-bin.tar.gz/\1/')"
  log "Maven ${ver} -> /opt/apache-maven-${ver}"
  $SUDO tar -xzf "$tarball" -C /opt
  $SUDO ln -sfn "/opt/apache-maven-${ver}" /opt/maven
  echo 'export PATH="/opt/maven/bin:$PATH"' | $SUDO tee /etc/profile.d/maven.sh >/dev/null
fi

# ---- Go --------------------------------------------------------------------
if compgen -G "${HERE}/artifacts/go/go*.linux-amd64.tar.gz" >/dev/null; then
  tarball="$(compgen -G "${HERE}/artifacts/go/go*.linux-amd64.tar.gz" | head -n1)"
  log "Go ($(basename "$tarball")) -> /usr/local/go"
  $SUDO rm -rf /usr/local/go
  $SUDO tar -xzf "$tarball" -C /usr/local
  echo 'export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"' | $SUDO tee /etc/profile.d/golang.sh >/dev/null
fi

# ---- Rust (standalone offline installer) -----------------------------------
if compgen -G "${HERE}/artifacts/rust/rust-*.tar.xz" >/dev/null; then
  tarball="$(compgen -G "${HERE}/artifacts/rust/rust-*.tar.xz" | head -n1)"
  log "Rust ($(basename "$tarball")) via the standalone installer..."
  tmp="$(mktemp -d)"
  tar -xJf "$tarball" -C "$tmp"
  $SUDO "$tmp"/rust-*/install.sh --without=rust-docs >/dev/null
  rm -rf "$tmp"
fi

# ---- Cloud tools -----------------------------------------------------------
if [[ -f "${HERE}/artifacts/k3s/k3s" ]]; then
  log "k3s (air-gap procedure: binary + preloaded images)..."
  $SUDO install -m 0755 "${HERE}/artifacts/k3s/k3s" /usr/local/bin/k3s
  $SUDO mkdir -p /var/lib/rancher/k3s/agent/images
  $SUDO cp "${HERE}/artifacts/k3s/k3s-airgap-images-amd64.tar.zst" /var/lib/rancher/k3s/agent/images/
  if [[ -d /run/systemd/system ]]; then
    INSTALL_K3S_SKIP_DOWNLOAD=true $SUDO env INSTALL_K3S_SKIP_DOWNLOAD=true sh "${HERE}/artifacts/k3s/install.sh" >/dev/null
  else
    warn "No systemd: k3s binary installed; service setup skipped."
  fi
fi
if compgen -G "${HERE}/artifacts/helm/helm-*-linux-amd64.tar.gz" >/dev/null; then
  tarball="$(compgen -G "${HERE}/artifacts/helm/helm-*-linux-amd64.tar.gz" | head -n1)"
  log "Helm ($(basename "$tarball"))"
  tmp="$(mktemp -d)"; tar -xzf "$tarball" -C "$tmp"
  $SUDO install -m 0755 "$tmp/linux-amd64/helm" /usr/local/bin/helm
  rm -rf "$tmp"
fi
if [[ -f "${HERE}/artifacts/k9s/k9s_linux_amd64.deb" ]]; then
  log "k9s"
  $SUDO dpkg -i "${HERE}/artifacts/k9s/k9s_linux_amd64.deb" >/dev/null
fi
if [[ -f "${HERE}/artifacts/aws/awscliv2.zip" ]]; then
  log "AWS CLI v2"
  tmp="$(mktemp -d)"
  unzip -q "${HERE}/artifacts/aws/awscliv2.zip" -d "$tmp"
  $SUDO "$tmp/aws/install" --update >/dev/null
  rm -rf "$tmp"
fi
if compgen -G "${HERE}/artifacts/ansible/*.whl" >/dev/null; then
  log "Ansible (offline pipx install from bundled wheels)"
  if command -v pipx >/dev/null 2>&1; then
    pipx install --pip-args "--no-index --find-links ${HERE}/artifacts/ansible" --include-deps ansible >/dev/null \
      || warn "pipx install of ansible failed — try manually with the wheels in artifacts/ansible/"
  else
    warn "pipx not present (python module not packed?) — ansible wheels are in artifacts/ansible/"
  fi
fi

# ---- Ollama ----------------------------------------------------------------
if [[ -f "${HERE}/artifacts/ollama/ollama-linux-amd64.tgz" ]]; then
  log "Ollama (documented manual install: untar into /usr)"
  $SUDO tar -C /usr -xzf "${HERE}/artifacts/ollama/ollama-linux-amd64.tgz"
fi

# ---- Container images + compose stacks -------------------------------------
if [[ -f "${HERE}/images/stack-images.tar.gz" ]]; then
  if command -v docker >/dev/null 2>&1 && $SUDO docker info >/dev/null 2>&1; then
    log "Loading container images (elastic/opensearch)..."
    gunzip -c "${HERE}/images/stack-images.tar.gz" | $SUDO docker load
  else
    warn "Docker daemon not running — load later with: gunzip -c images/stack-images.tar.gz | docker load"
  fi
  # Exact packed image versions, recorded at pack time.
  ELASTIC_VERSION="" OPENSEARCH_VERSION=""
  [[ -f "${HERE}/config/stack-versions.env" ]] && . "${HERE}/config/stack-versions.env"
  for stack in elastic opensearch; do
    if [[ -d "${HERE}/config/${stack}" ]]; then
      dest="${HOME}/${stack}"
      mkdir -p "$dest"
      cp "${HERE}/config/${stack}/docker-compose.yml" "$dest/"
      if [[ ! -f "$dest/.env" ]] && command -v openssl >/dev/null 2>&1; then
        if [[ "$stack" == elastic ]]; then
          printf 'ELASTIC_VERSION=%s\nELASTIC_PASSWORD=%s\nKIBANA_PASSWORD=%s\nES_HEAP=2g\n' \
            "${ELASTIC_VERSION:-latest}" "$(openssl rand -base64 18 | tr -d '/+=')" \
            "$(openssl rand -base64 18 | tr -d '/+=')" > "$dest/.env"
        else
          printf 'OPENSEARCH_VERSION=%s\nOPENSEARCH_ADMIN_PASSWORD=%sAa1!\nOPENSEARCH_HEAP=2g\n' \
            "${OPENSEARCH_VERSION:-latest}" "$(openssl rand -base64 18 | tr -d '/+=')" > "$dest/.env"
        fi
        chmod 600 "$dest/.env"
      fi
      log "${stack}: compose stack staged in ${dest} (start with: cd ${dest} && docker compose up -d)"
    fi
  done
fi

# ---- VS Code extensions ----------------------------------------------------
if compgen -G "${HERE}/vsix/*.vsix" >/dev/null && command -v code >/dev/null 2>&1; then
  log "Installing $(ls "${HERE}"/vsix/*.vsix | wc -l) VS Code extensions from .vsix..."
  if [[ -z "$SUDO" ]]; then
    warn "Running as root — install extensions later as the desktop user:"
    warn "  for f in vsix/*.vsix; do code --install-extension \"\$f\"; done"
  else
    for f in "${HERE}"/vsix/*.vsix; do
      code --install-extension "$f" >/dev/null 2>&1 || warn "  $(basename "$f") failed"
    done
  fi
fi

log "Done. Open a new shell for PATH updates (Go, Maven). SBOM provenance: ./sbom.cdx.json"
