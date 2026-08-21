# dev-setup

Development environment setup: an **interactive, idempotent installer** for a
full dev toolchain on Ubuntu 26.04 — each tool individually prompted, every
module safe to re-run.

Tools covered: Git, Claude Code (+ a curated plugin set), VS Code (+ a
curated extension set), Docker (+ NVIDIA Container Toolkit), Podman
(rootless, as a Docker alternative), JDK 25 LTS,
Maven, C/C++ (GCC/Clang, plus the newest LLVM release), Go, Rust, Python,
cloud dev tools (k3s, Helm, k9s, Ansible, AWS CLI), the Proton apps with
Linux support (VPN, Mail + bundled Calendar, Bridge, Drive CLI, Pass, Meet,
Authenticator — one module and flag each), Elastic Stack (Basic license, in
Docker), OpenSearch Platform (the Apache-2.0 Elastic alternative, in
Docker), and Ollama. See [docs/dev-tools.md](docs/dev-tools.md) for the
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

Every component has a matching flag (`--docker`, `--opensearch`, ...; see
`./scripts/setup.sh --list`), and `--modules` takes a comma-separated list —
interactively they pre-scope the menu, unattended they install exactly the
selection: `DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh --docker --opensearch`

The target operating system is prompted for interactively (or `--os` for
unattended runs) and **defaults to Ubuntu**; components not supported on the
target are warned about and skipped unattended — see the
[support matrix](docs/dev-tools.md#target-operating-systems).

Air-gapped enclave? `./scripts/offline-bundle.sh --pack` uses the
[SBOM](sbom.cdx.json) to package everything the selected components need
into one archive with a self-contained offline installer — see
[offline installs](docs/dev-tools.md#offline--air-gapped-installs).

Removing things? `./scripts/uninstall.sh` mirrors the same selection
contract (all components by default, per-component prompts, the same
flags), keeps user data unless `--purge-data`, and never removes `python3`
— see [uninstalling](docs/dev-tools.md#uninstalling).

## Documentation

| Doc | What's inside |
|---|---|
| [Module reference](docs/dev-tools.md) | Every module — what it installs and from where; the component-selection flags (`--modules`, one flag per component) with examples; dependency-ordering notes; and the [post-install verification](docs/dev-tools.md#after-it-finishes) commands |
| [Troubleshooting](docs/troubleshooting.md) | Symptom-first fixes: [Elasticsearch](docs/troubleshooting.md#elasticsearch-container-exits-immediately) / [OpenSearch](docs/troubleshooting.md#opensearch-container-exits-immediately) containers exiting at start, [Docker only working with sudo](docs/troubleshooting.md#docker-works-with-sudo-only), and [Ollama running on CPU](docs/troubleshooting.md#ollama-runs-on-cpu) |
| [WorkSpace design spec](docs/superpowers/specs/2026-08-12-workspace-dev-environment-design.md) | Archived design reference for an AWS WorkSpace cloud dev desktop — a separate effort, not part of this installer |
| [Software bill of materials](sbom.cdx.json) | CycloneDX 1.6 SBOM of **everything the installer delivers**: every distro package, vendor repo/.deb, tarball, container image, VS Code extension, and Claude Code plugin the modules install, with suppliers, licenses, and pinned-vs-latest resolution per component (maintained alongside `config/versions.env`) |

The OS-level story (dual-boot install, NVIDIA driver, kernel) is documented
in [asanderson/dual-boot](https://github.com/asanderson/dual-boot), which has
its own documentation map.

## Repo layout

```
docs/
  dev-tools.md           Module table, ordering notes, post-install verification
  troubleshooting.md     Elastic / OpenSearch / Docker / Ollama fixes
scripts/
  setup.sh               Interactive orchestrator for the modules below
  lib/common.sh          Shared helpers (prompts, apt, logging)
  modules/*.sh           One idempotent installer per tool
config/
  versions.env           Pinned versions for artifact-based installs
  elastic/               Docker Compose for Elasticsearch + Kibana (Basic license)
  opensearch/            Docker Compose for OpenSearch + Dashboards (Apache-2.0)
```

## Testing

Every PR runs the installer end-to-end in a **fresh Ubuntu 26.04 container**
(`.github/workflows/container-test.yml`): all default modules under
`DEV_SETUP_ASSUME_YES=1`, a second pass to prove idempotency, and per-module
version probes — plus shellcheck across every script. A separate **GPU-path
job** stubs `nvidia-smi` as the MSI Raider's RTX 5090 to exercise the
GPU-present branches (NVIDIA Container Toolkit install, nvidia runtime
registration, Ollama's GPU path) that the GPU-less matrix can't reach. Run
them locally with Docker: `./test/container-test.sh --rerun` and
`./test/container-test.sh --gpu-path`.

## Repeatability notes

- Modules are **idempotent** — re-run `setup.sh` any time; already-installed
  tools update or no-op.
- Artifact-based installs (Maven, Elastic, OpenSearch) are **pinned** in
  `config/versions.env`; apt/rustup/go-based installs track their official
  channels. Bump the pins deliberately and re-run the module.
- Everything third-party comes from **official sources only**: vendor apt
  repos with GPG keyrings, checksummed tarballs, or vendor install scripts.
