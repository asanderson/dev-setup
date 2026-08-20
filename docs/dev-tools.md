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

> **GPU note:** if this machine has an NVIDIA GPU, install the driver first —
> the NVIDIA Container Toolkit and Ollama acceleration key off it. For the
> MSI Raider 18 dual-boot machine that runbook lives in
> [asanderson/dual-boot](https://github.com/asanderson/dual-boot).

| Module | What you get | Method |
|---|---|---|
| Git | Latest stable git + git-lfs | git-core PPA (optional) |
| Claude Code | Anthropic's coding CLI | Official native installer (auto-updating; npm route is deprecated) |
| Docker | Engine + Buildx + Compose v2, docker group, NVIDIA Container Toolkit | Official Docker apt repo |
| JDK | Java 25 LTS | Ubuntu OpenJDK **or** Eclipse Temurin (Adoptium repo) |
| Maven | Pinned Apache Maven (see `config/versions.env`) | Apache dist tarball → `/opt/maven`, SHA-512 verified |
| C/C++ | GCC, Clang/LLVM, CMake, Ninja, gdb, valgrind, ccache | Ubuntu archive |
| Go | Latest stable (resolved from go.dev) | Official tarball → `/usr/local/go` |
| Rust | Stable toolchain + clippy + rustfmt | rustup |
| Python | Python 3 + venv, pip, dev headers, pipx | Ubuntu archive |
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
