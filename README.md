# dev-setup

Development environment setup: an **interactive, idempotent installer** for a
full dev toolchain on Ubuntu 26.04 — each tool individually prompted, every
module safe to re-run.

Tools covered: Git, Claude Code, Docker (+ NVIDIA Container Toolkit),
JDK 25 LTS, Maven, C/C++ (GCC/Clang), Go, Rust, Elastic Stack (Basic license,
in Docker), and Ollama. See [docs/dev-tools.md](docs/dev-tools.md) for the
full module table.

> **Setting up the dual-boot laptop first?** The OS-level runbook — Windows
> prep, Ubuntu 26.04 install, NVIDIA driver, kernel — lives in
> [asanderson/dual-boot](https://github.com/asanderson/dual-boot). Run that
> to completion, then come back here for the dev tools.

## Quick start

```bash
git clone https://github.com/asanderson/dev-setup.git ~/dev-setup
cd ~/dev-setup
./scripts/setup.sh              # interactive: pick your dev tools
```

Unattended (accept every prompt): `DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh`

## Repo layout

```
docs/
  dev-tools.md           Module table, ordering notes, post-install verification
  troubleshooting.md     Elastic / Docker / Ollama fixes
scripts/
  setup.sh               Interactive orchestrator for the modules below
  lib/common.sh          Shared helpers (prompts, apt, logging)
  modules/*.sh           One idempotent installer per tool
config/
  versions.env           Pinned versions for artifact-based installs
  elastic/               Docker Compose for Elasticsearch + Kibana (Basic license)
```

## Testing

Every PR runs the installer end-to-end in a **fresh Ubuntu 26.04 container**
(`.github/workflows/container-test.yml`): all default modules under
`DEV_SETUP_ASSUME_YES=1`, a second pass to prove idempotency, and per-module
version probes — plus shellcheck across every script. Run it locally with
Docker: `./test/container-test.sh --rerun`.

## Repeatability notes

- Modules are **idempotent** — re-run `setup.sh` any time; already-installed
  tools update or no-op.
- Artifact-based installs (Maven, Elastic) are **pinned** in
  `config/versions.env`; apt/rustup/go-based installs track their official
  channels. Bump the pins deliberately and re-run the module.
- Everything third-party comes from **official sources only**: vendor apt
  repos with GPG keyrings, checksummed tarballs, or vendor install scripts.
