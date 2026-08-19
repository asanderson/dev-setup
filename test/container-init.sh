#!/usr/bin/env bash
# container-init.sh — runs INSIDE a fresh Ubuntu container (as root).
# Bootstraps a non-root user with passwordless sudo, scopes setup.sh to the
# requested modules, runs the installer unattended, and verifies the results.
#
# Invoked by test/container-test.sh — not meant to be run on a real machine.
#
# Usage: container-init.sh "<space-separated module list>" [rerun]
# Mounts expected: /repo (this repository, read-only).
# Optional proxy support: if $https_proxy is set, apt sources switch to
# HTTPS and route through it; if /ccr-ca.crt is mounted, it is trusted
# (for CONNECT-only MITM proxies, e.g. sandboxed CI environments).
set -euo pipefail

MODULES_OVERRIDE="${1:?module list required}"
RERUN="${2:-}"

echo "### [init] apt bootstrap$( [[ -n "${https_proxy:-}" ]] && echo ' (via proxy)' )"
unset http_proxy HTTP_PROXY   # CONNECT-only proxies reject plain-HTTP proxying
if [[ -n "${https_proxy:-}" ]]; then
  sed -i 's|http://\(archive\|security\).ubuntu.com|https://\1.ubuntu.com|g' \
    /etc/apt/sources.list.d/ubuntu.sources
  {
    echo "Acquire::https::Proxy \"${https_proxy}\";"
    [[ -f /ccr-ca.crt ]] && echo 'Acquire::https::CAInfo "/ccr-ca.crt";'
  } >/etc/apt/apt.conf.d/95proxy
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates sudo curl gnupg openssl >/dev/null
if [[ -f /ccr-ca.crt ]]; then
  cp /ccr-ca.crt /usr/local/share/ca-certificates/agent-proxy.crt
  update-ca-certificates >/dev/null
fi

echo "### [init] create test user 'dev' with passwordless sudo"
useradd -m -s /bin/bash dev
echo 'dev ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dev
echo 'Defaults env_keep += "https_proxy no_proxy HTTPS_PROXY NO_PROXY DEBIAN_FRONTEND"' >/etc/sudoers.d/proxy-env
chmod 440 /etc/sudoers.d/dev /etc/sudoers.d/proxy-env

echo "### [init] copy repo, scope modules to: ${MODULES_OVERRIDE}"
cp -r /repo /home/dev/dev-setup
sed -i "s/^MODULES=(.*)$/MODULES=(${MODULES_OVERRIDE})/" /home/dev/dev-setup/scripts/setup.sh
grep -n '^MODULES=' /home/dev/dev-setup/scripts/setup.sh
chown -R dev:dev /home/dev/dev-setup

run_setup() {
  sudo -u dev -H env \
    https_proxy="${https_proxy:-}" no_proxy="${no_proxy:-}" \
    DEV_SETUP_ASSUME_YES=1 \
    bash -c 'cd ~/dev-setup && ./scripts/setup.sh'
}

echo "### [run] setup.sh under DEV_SETUP_ASSUME_YES=1"
set +e; run_setup; rc=$?; set -e
echo "### [run] setup.sh exit code: ${rc}"

if [[ "$RERUN" == "rerun" ]]; then
  echo "### [rerun] second pass — idempotency check"
  set +e; run_setup; rc2=$?; set -e
  echo "### [rerun] second pass exit code: ${rc2}"
  [[ $rc -eq 0 && $rc2 -ne 0 ]] && rc=$rc2
fi

echo "### [verify] installed tools for selected modules (login shell as dev)"
verify_rc=0
for m in ${MODULES_OVERRIDE}; do
  case "$m" in
    git)         probes=("git --version") ;;
    claude-code) probes=('$HOME/.local/bin/claude --version') ;;
    docker)      probes=("docker --version" "docker compose version") ;;
    jdk)         probes=("java -version") ;;
    maven)       probes=("mvn -version") ;;
    cpp)         probes=("gcc --version" "clang --version" "cmake --version") ;;
    golang)      probes=("go version") ;;
    rust)        probes=("rustc --version" "cargo --version") ;;
    elastic|ollama) echo "  SKIP ${m} (no probe in container)"; continue ;;
    *)           echo "  SKIP ${m} (unknown module)"; continue ;;
  esac
  for probe in "${probes[@]}"; do
    if out=$(sudo -u dev -H bash -lc "$probe" 2>&1 | head -n1); then
      printf '  OK   %-12s %s\n' "$m" "$out"
    else
      printf '  FAIL %-12s probe failed: %s\n' "$m" "$probe"
      verify_rc=1
    fi
  done
done
[[ $rc -eq 0 && $verify_rc -ne 0 ]] && rc=$verify_rc

echo "### [done] overall exit: ${rc}"
exit "${rc}"
