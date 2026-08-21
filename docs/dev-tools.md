# Dev tools — `scripts/setup.sh`

Interactive development-environment installer for Ubuntu 26.04. Each
component prompts y/n; modules are idempotent and safe to re-run.
`DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh` accepts everything for an
unattended run.

Every component also has a command-line flag (`--git`, `--docker`,
`--opensearch`, ...; `./scripts/setup.sh --list` prints them all), and
`--modules git,docker,rust` takes a comma-separated list. Interactive runs
still confirm each component — the flags just pre-scope the menu; unattended
runs install exactly the selected components:

```bash
./scripts/setup.sh --docker --opensearch                     # offer only these two
DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh --docker --opensearch   # install exactly these two
DEV_SETUP_ASSUME_YES=1 ./scripts/setup.sh                    # install everything
```

Selection order never matters: components always install in dependency
order (Docker before Elastic/OpenSearch, JDK before Maven).

## Offline / air-gapped installs

`scripts/offline-bundle.sh --pack` builds a **self-contained archive** for
enclaves with no network (Ubuntu 26.04 amd64 targets). The
[SBOM](../sbom.cdx.json) is the component manifest: pinned versions come
from it, latest-resolved components are resolved once at pack time, and the
bundle records exactly what was packed (`MANIFEST.sha256` + a copy of the
SBOM as provenance). The apt dependency closure is computed in a **fresh
container**, so the bundle is complete for a clean machine regardless of
what the packing host has installed.

```bash
./scripts/offline-bundle.sh --pack                      # all offline-packagable components
./scripts/offline-bundle.sh --pack --modules git,python,cloud
# → dev-setup-offline-<date>.tar.gz  (transfer into the enclave, untar, then:)
./dev-setup-offline-<date>/install-offline.sh           # verifies checksums, installs; no network, no repo
```

Offline-packagable: git (archive, no PPA), vscode + extensions (.vsix),
docker, podman, jdk, maven, cpp (+ LLVM), golang, rust (standalone
installer), python, cloud (k3s air-gap procedure with preloaded images,
Helm, k9s, Ansible wheels, AWS CLI), elastic + opensearch (saved container
images + compose configs), ollama. **Not packagable** — network services
that cannot function in an enclave: claude-code (+ plugins) and the
proton-* apps.

## Target operating systems

Interactive runs prompt for the target OS; non-interactive runs take
`--os` — the **default is `ubuntu`** either way, the platform every module
is written and tested for. Catalog: `ubuntu debian pureos rocky rhel qubes
windows`. The installer configures the machine it runs on, so it verifies
`/etc/os-release` matches the declared target before installing anything;
`qubes` and `windows` are in the catalog for honest guidance (use a
Debian-template qube with `--os debian`; use WSL2 Ubuntu with `--os
ubuntu`) rather than installs.

Components whose installer can't work on the target OS are **warned
about**: unattended runs never install them; interactive runs may force one
(default no). Support follows each module's package sources, as written:

Almost every component now installs on **every target OS**, dispatching per
family to the right installer and packages — apt vs dnf, vendor `.deb` vs
`.rpm`, Microsoft's apt vs yum repos:

| Supported on | Components | How |
|---|---|---|
| Everywhere (all five) | Git, C/C++, VS Code, JDK, Python, Cloud tools, Podman, Claude Code (+ plugins), Maven, Go, Rust, Ollama, Elastic, OpenSearch, Proton Mail/Bridge/Drive CLI/Pass/Meet/Authenticator | distro packages per family (git-core PPA extra on Ubuntu; newest-LLVM extra on Ubuntu/Debian, where apt.llvm.org has suites); Microsoft's apt/yum repos; Proton's `.deb`/`.rpm` builds; distro-agnostic installers and tarballs |
| Ubuntu, Debian, Rocky, RHEL (no PureOS) | Docker | Docker's official repos: apt suites for Ubuntu/Debian, dnf repos for centos(Rocky)/RHEL — no PureOS suite exists; use Podman there |
| Debian family only (ubuntu, debian, pureos) | Proton VPN | Proton's official Linux VPN app ships apt packages only — no Enterprise Linux channel exists |

> **GPU note:** if this machine has an NVIDIA GPU, install the driver first —
> the NVIDIA Container Toolkit and Ollama acceleration key off it. For the
> MSI Raider 18 dual-boot machine that runbook lives in
> [asanderson/dual-boot](https://github.com/asanderson/dual-boot).

| Module | What you get | Method |
|---|---|---|
| Git | Latest stable git + git-lfs | git-core PPA (optional) |
| Claude Code | Anthropic's coding CLI | Official native installer (auto-updating; npm route is deprecated) |
| Claude Code plugins | superpowers, caveman, karpathy-skills, ecc, claude-mem, agentic-awesome-skills, gsd-core — latest releases | `claude plugin` marketplaces (each plugin's GitHub repo) |
| VS Code | Visual Studio Code, stable channel + curated extensions (Claude Code, Codex, Python, C/C++, Java, rust-analyzer, Ansible, YAML, Go, CodeLLDB, Remote Development/Explorer/SSH-edit, Kubernetes, Docker, AWS Toolkit, GitHub Repositories, GitLab, gitignore, GitLens) | Microsoft apt repo; extensions from the VS Code Marketplace at the newest compatible version |
| Docker | Engine + Buildx + Compose v2, docker group, NVIDIA Container Toolkit | Official Docker repos (apt on Ubuntu/Debian; dnf on Rocky/RHEL) |
| Podman | Rootless, daemonless containers **running as your user** — the Docker alternative; coexists with Docker (skip the `podman-docker` shim if both) | Ubuntu/Debian archives; native dnf package on Rocky/RHEL |
| JDK | Java 25 LTS | Ubuntu OpenJDK **or** Eclipse Temurin (Adoptium repo) |
| Maven | Pinned Apache Maven (see `config/versions.env`) | Apache dist tarball → `/opt/maven`, SHA-512 verified |
| C/C++ | GCC, Clang/LLVM, CMake, Ninja, gdb, valgrind, ccache — plus the newest Clang/LLVM release as versioned `clang-N` packages | Ubuntu archive + official apt.llvm.org repo |
| Go | Latest stable (resolved from go.dev) | Official tarball → `/usr/local/go` |
| Rust | Stable toolchain + clippy + rustfmt | rustup |
| Python | Python 3 + venv, pip, dev headers, pipx | Ubuntu archive |
| Cloud | k3s (+ bundled kubectl), Helm, k9s, Ansible, AWS CLI v2 — latest stable releases | Official k3s/Helm install scripts; k9s from its GitHub releases; Ansible from PyPI via pipx; AWS CLI official bundle |
| Proton VPN | Official GNOME desktop app (CLI available) | Proton's apt repo (bootstrap .deb sha256-pinned against Proton's published checksum) |
| Proton Mail | Desktop app, **bundles Proton Calendar** (no standalone Linux Calendar app exists) | Official latest-version .deb; app self-updates |
| Proton Bridge | IMAP/SMTP bridge for mail clients (paid plans) | Official .deb from Proton's version feed, **GPG-signature-verified**; self-updates |
| Proton Drive | **CLI** (Proton ships no Linux GUI app for Drive yet) | Official static binary from Proton's version feed, SHA512-verified |
| Proton Pass | Password manager desktop app | Official latest-version .deb; app self-updates |
| Proton Meet | E2E-encrypted videoconferencing desktop app | Official latest-version .deb; app self-updates |
| Proton Authenticator | TOTP two-factor app | Official latest-version .deb; app self-updates |
| Elastic Stack | Elasticsearch + Kibana, **Basic license**, single node | Docker Compose (`~/elastic`), generated credentials |
| OpenSearch | OpenSearch + Dashboards, **Apache-2.0, no license tiers** — the Elastic alternative (OpenSearch Software Foundation / Linux Foundation), single node | Docker Compose (`~/opensearch`), generated credentials |
| Ollama | Local LLM runtime, GPU-accelerated | Official install script |

Pick Elastic, OpenSearch, or both — the OpenSearch stack's ports are offset
(9201 REST, 5602 Dashboards) so the two dev stacks coexist.

Order notes handled for you: Docker before Elastic/OpenSearch, JDK before Maven, and
GPU-dependent pieces detect the driver at runtime (with a `sudo docker`
fallback when fresh `docker`-group membership hasn't reached the current
session yet).

## After it finishes

```bash
exec bash -l                              # pick up PATH changes
docker run --rm hello-world               # docker group active? (else log out/in)
docker run --rm --gpus all ubuntu nvidia-smi   # GPU visible in containers
curl -s -u elastic:<pw> http://localhost:9200/_license    # "type":"basic"
curl -sk -u admin:<pw> https://localhost:9201             # OpenSearch (demo TLS cert, hence -k)
ollama run llama3.2                       # first model
```

Elastic credentials are generated into `~/elastic/.env` (mode 600); Kibana is
at <http://localhost:5601> (user `elastic`). OpenSearch credentials likewise
land in `~/opensearch/.env`; Dashboards is at <http://localhost:5602> (user
`admin`). All four services bind to localhost only.

Anything misbehaving → [troubleshooting](troubleshooting.md).
