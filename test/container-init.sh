#!/usr/bin/env bash
# container-init.sh — runs INSIDE a fresh Ubuntu container (as root).
# Bootstraps a non-root user with passwordless sudo, runs the installer
# unattended scoped to the requested modules (via setup.sh --modules, which
# doubles as the CI test of the component-selection flags), and verifies
# the results.
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

echo "### [init] copy repo; will scope via: setup.sh --modules ${MODULES_OVERRIDE// /,}"
cp -r /repo /home/dev/dev-setup
chown -R dev:dev /home/dev/dev-setup

run_setup() {
  sudo -u dev -H env \
    https_proxy="${https_proxy:-}" no_proxy="${no_proxy:-}" \
    DEV_SETUP_ASSUME_YES=1 \
    bash -c "cd ~/dev-setup && ./scripts/setup.sh --modules ${MODULES_OVERRIDE// /,}"
}

echo "### [flags] target-OS argument contract"
rc=0
sudo -u dev -H bash -c 'cd ~/dev-setup && ./scripts/setup.sh --os bogus' >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || { echo "FAIL: --os bogus must exit 2 (got ${rc})"; exit 1; }
rc=0
out="$(sudo -u dev -H env DEV_SETUP_ASSUME_YES=1 \
  bash -c 'cd ~/dev-setup && ./scripts/setup.sh --os rocky --proton-vpn --claude-code' 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || { echo "FAIL: --os rocky on an ubuntu machine must fail"; exit 1; }
grep -q "proton-vpn: not supported on rocky" <<<"$out" \
  || { echo "FAIL: missing unsupported-component warning"; exit 1; }
grep -q "unattended runs never install unsupported" <<<"$out" \
  || { echo "FAIL: missing unattended skip notice"; exit 1; }
grep -q "the installer configures the system it runs on" <<<"$out" \
  || { echo "FAIL: missing target/machine mismatch guard"; exit 1; }
echo "  PASS: --os validation (exit 2), unsupported-component warn+skip, mismatch guard"

echo "### [flags] ollama-models refuses cleanly without Ollama"
rc=0
out="$(sudo -u dev -H env DEV_SETUP_ASSUME_YES=1 \
  bash -c 'cd ~/dev-setup && ./scripts/setup.sh --modules ollama-models' 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || { echo "FAIL: ollama-models must fail when Ollama is absent"; exit 1; }
grep -q "Ollama is not installed" <<<"$out" \
  || { echo "FAIL: missing the run-with---ollama-first guidance"; exit 1; }
echo "  PASS: ollama-models dependency contract"

echo "### [flags] runtime-dependent modules refuse cleanly without their runtime"
rc=0
out="$(sudo -u dev -H env DEV_SETUP_ASSUME_YES=1 \
  bash -c 'cd ~/dev-setup && ./scripts/setup.sh --openclaw' 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || { echo "FAIL: openclaw must fail when Node.js (nvm) is absent"; exit 1; }
grep -q "Node.js is not installed" <<<"$out" \
  || { echo "FAIL: missing the run-with---nodejs guidance"; exit 1; }
rc=0
out="$(sudo -u dev -H env DEV_SETUP_ASSUME_YES=1 \
  bash -c 'cd ~/dev-setup && ./scripts/setup.sh --vllm' 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || { echo "FAIL: vllm must fail when uv is absent"; exit 1; }
grep -q "uv is not installed" <<<"$out" \
  || { echo "FAIL: missing the run-with---python guidance"; exit 1; }
echo "  PASS: openclaw needs nodejs, vllm needs python (uv)"

echo "### [flags] hardware/vendor-gated modules: clean skip or clean refusal"
rc=0
out="$(sudo -u dev -H env DEV_SETUP_ASSUME_YES=1 \
  bash -c 'cd ~/dev-setup && ./scripts/setup.sh --nvidia-driver' 2>&1)" || rc=$?
[[ $rc -eq 0 ]] || { echo "FAIL: nvidia-driver must skip cleanly (exit 0) without an NVIDIA GPU (got ${rc})"; exit 1; }
grep -q "No NVIDIA GPU detected" <<<"$out" \
  || { echo "FAIL: missing the no-GPU skip notice"; exit 1; }
rc=0
out="$(sudo -u dev -H env DEV_SETUP_ASSUME_YES=1 \
  bash -c 'cd ~/dev-setup && ./scripts/setup.sh --vmware-workstation' 2>&1)" || rc=$?
[[ $rc -ne 0 ]] || { echo "FAIL: vmware-workstation must fail without a downloaded bundle"; exit 1; }
grep -q "Broadcom requires a (free) support-portal login" <<<"$out" \
  || { echo "FAIL: missing the download-the-bundle guidance"; exit 1; }
# A pre-26H1 bundle (17.x) is refused before anything runs it.
sudo -u dev -H bash -c 'printf "#!/bin/sh\necho SHOULD-NOT-RUN\n" >/tmp/VMware-Workstation-Full-17.6.4-24832109.x86_64.bundle'
rc=0
out="$(sudo -u dev -H env DEV_SETUP_ASSUME_YES=1 \
  DEV_SETUP_VMWARE_BUNDLE=/tmp/VMware-Workstation-Full-17.6.4-24832109.x86_64.bundle \
  bash -c 'cd ~/dev-setup && ./scripts/setup.sh --vmware-workstation' 2>&1)" || rc=$?
[[ $rc -ne 0 ]] && grep -q "installs VMware Workstation Pro 26H1 or newer" <<<"$out" \
  && ! grep -q SHOULD-NOT-RUN <<<"$out" \
  || { echo "FAIL: vmware-workstation must refuse a 17.x bundle without running it (rc=${rc})"; exit 1; }
rc=0
out="$(sudo -u dev -H bash -c 'cd ~/dev-setup && ./scripts/setup.sh --os windows' 2>&1)" || rc=$?
[[ $rc -ne 0 ]] && grep -q "setup.ps1" <<<"$out" \
  || { echo "FAIL: --os windows must point at scripts/setup.ps1"; exit 1; }
rc=0
out="$(sudo -u dev -H env DEV_SETUP_ASSUME_YES=1 \
  bash -c 'cd ~/dev-setup && ./scripts/setup.sh --amazon-workspaces' 2>&1)" || rc=$?
# Amazon ships no client for 26.04 yet: the module must refuse with
# guidance rather than half-install the 24.04 build (whose libicu74/libxml2
# dependencies 26.04 lacks). Flip this to an install probe once Amazon
# publishes a resolute suite.
[[ $rc -ne 0 ]] && grep -q "Amazon publishes no WorkSpaces client for" <<<"$out" \
  || { echo "FAIL: amazon-workspaces must refuse cleanly on a release without an Amazon suite (rc=${rc})"; exit 1; }
echo "  PASS: nvidia-driver no-GPU skip, vmware bundle guidance + pre-26H1 refusal, windows -> setup.ps1, workspaces no-suite refusal"

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
    nodejs)      probes=('. $HOME/.nvm/nvm.sh && nvm --version' "node --version" "npm --version" '$HOME/.bun/bin/bun --version') ;;
    claude-code) probes=('$HOME/.local/bin/claude --version') ;;
    vscode)      probes=("code --version") ;;
    docker)      probes=("docker --version" "docker compose version") ;;
    podman)      probes=("podman --version") ;;
    jdk)         probes=("java -version") ;;
    maven)       probes=("mvn -version") ;;
    cpp)         probes=("gcc --version" "clang --version" "cmake --version") ;;
    golang)      probes=("go version") ;;
    rust)        probes=("rustc --version" "cargo --version") ;;
    python)      probes=("python3 --version" "pip3 --version" "pipx --version" '$HOME/.local/bin/uv --version') ;;
    cloud)       probes=("k3s --version" "helm version --short" "k9s version" "ansible --version" "aws --version") ;;
    claude-plugins) probes=('$HOME/.local/bin/claude plugin list') ;;
    proton-vpn)  probes=("dpkg -s proton-vpn-gnome-desktop") ;;
    proton-mail) probes=("dpkg -s proton-mail") ;;
    proton-bridge) probes=("dpkg -s protonmail-bridge") ;;
    proton-drive)  probes=("proton-drive --version") ;;
    proton-pass)   probes=("dpkg -s proton-pass") ;;
    proton-meet)   probes=("dpkg -s proton-meet") ;;
    proton-authenticator) probes=("dpkg -s proton-authenticator") ;;
    codex)       probes=('$HOME/.local/bin/codex --version') ;;
    opencode)    probes=('$HOME/.local/bin/opencode --version') ;;
    oh-my-pi)    probes=('PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH" omp --version') ;;
    hermes-agent) probes=('test -x $HOME/.local/bin/hermes && echo "hermes launcher present"') ;;
    openclaw)    probes=("openclaw --version") ;;
    strata)      probes=('test -x $HOME/.local/bin/strata && echo "strata terminal present"') ;;
    7zip)        probes=("7zz | grep -m1 '7-Zip'" "7z | grep -m1 '7-Zip'") ;;
    libreoffice) probes=("libreoffice --version") ;;
    amazon-workspaces) probes=("dpkg -s workspacesclient") ;;
    llama-cpp)   probes=('$HOME/.local/bin/llama-cli --version' 'test -x $HOME/.local/bin/llama-server && echo llama-server') ;;
    koboldcpp)   probes=('test -x $HOME/.local/bin/koboldcpp && cat $HOME/.local/opt/koboldcpp/VERSION') ;;
    elastic|opensearch|ollama|ollama-models|nvidia-driver|cuda-toolkit|vmware-workstation|ik-llama-cpp|ktransformers|vllm)
      echo "  SKIP ${m} (no probe in container)"; continue ;;
    *)           echo "  SKIP ${m} (unknown module)"; continue ;;
  esac
  for probe in "${probes[@]}"; do
    # Capture fully, truncate after: piping through `head -n1` under
    # pipefail SIGPIPEs multi-line probes (k3s --version prints several
    # lines) into random 141 failures.
    if out=$(sudo -u dev -H bash -lc "$probe" 2>&1); then
      printf '  OK   %-12s %s\n' "$m" "${out%%$'\n'*}"
    else
      printf '  FAIL %-12s probe failed: %s\n' "$m" "$probe"
      verify_rc=1
    fi
  done
done
[[ $rc -eq 0 && $verify_rc -ne 0 ]] && rc=$verify_rc

# Optional round trip: uninstall the same set unattended and verify removal
# (and that python3 — an OS dependency — is never removed).
if [[ "$RERUN" == "uninstall-check" ]]; then
  echo "### [uninstall] removing the same set unattended"
  set +e
  sudo -u dev -H env DEV_SETUP_ASSUME_YES=1 \
    bash -c "cd ~/dev-setup && ./scripts/uninstall.sh --modules ${MODULES_OVERRIDE// /,}"
  urc=$?
  set -e
  echo "### [uninstall] uninstall.sh exit code: ${urc}"
  for m in ${MODULES_OVERRIDE}; do
    case "$m" in
      git)
        if sudo -u dev -H bash -lc 'command -v git' >/dev/null 2>&1; then
          echo "  FAIL git still present"; urc=1
        else echo "  OK   git removed"; fi ;;
      maven)
        if [[ -e /opt/maven ]]; then echo "  FAIL maven still present"; urc=1
        else echo "  OK   maven removed"; fi ;;
      jdk)
        if sudo -u dev -H bash -lc 'command -v java' >/dev/null 2>&1; then
          echo "  FAIL java still present"; urc=1
        else echo "  OK   jdk removed"; fi ;;
      python)
        if sudo -u dev -H bash -lc 'command -v pipx' >/dev/null 2>&1; then
          echo "  FAIL pipx still present"; urc=1
        else echo "  OK   python extras removed"; fi ;;
      golang)
        if [[ -e /usr/local/go ]]; then echo "  FAIL go still present"; urc=1
        else echo "  OK   go removed"; fi ;;
      *) echo "  SKIP ${m} (no removal probe)" ;;
    esac
  done
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  FAIL python3 was removed — the uninstaller must never do that"; urc=1
  else
    echo "  OK   python3 preserved (OS dependency)"
  fi
  [[ $rc -eq 0 && $urc -ne 0 ]] && rc=$urc
fi

echo "### [done] overall exit: ${rc}"
exit "${rc}"
