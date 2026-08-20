# Troubleshooting

Hardware, boot, and NVIDIA-driver issues for the dual-boot laptop are covered
in [asanderson/dual-boot](https://github.com/asanderson/dual-boot) — this page
covers the dev tools installed by `scripts/setup.sh`.

## Elasticsearch container exits immediately

- `vm.max_map_count [65530] is too low` → the module sets this, but verify:
  `sysctl vm.max_map_count` should print `262144`
  (persisted in `/etc/sysctl.d/99-elastic.conf`).
- Check logs: `docker logs elasticsearch`. Memory-lock errors mean the
  `memlock` ulimits in the compose file were edited out — restore them.
- License says `trial` not `basic`: the compose file pins
  `xpack.license.self_generated.type=basic`; if you started the stack before
  with trial, run `docker compose down -v` (erases data) or POST
  `/_license/start_basic` to convert in place.

## OpenSearch container exits immediately

- `docker logs opensearch` mentioning the initial admin password → the
  password in `~/opensearch/.env` doesn't meet the image's strength rules
  (min 8 chars, upper+lower+digit+special, zxcvbn-strong). The generated one
  always passes; if you edited it, pick a stronger one and
  `docker compose up -d` again.
- `vm.max_map_count` too low → same fix as Elasticsearch above, persisted in
  `/etc/sysctl.d/99-opensearch.conf`.
- `curl https://localhost:9201` complains about the certificate: expected —
  the dev stack serves the security plugin's self-signed demo certs. Use
  `curl -k` (and replace the demo certs before exposing beyond localhost).

## Docker works with sudo only

Group membership hasn't landed in your session: `newgrp docker` for the
current shell, or log out/in. Verify with `id -nG | grep docker`.
(The Elastic and OpenSearch modules detect this case automatically and fall
back to `sudo docker` for that run.)

## Ollama runs on CPU

`ollama ps` shows `100% CPU`? Check `nvidia-smi` works first (driver — see
the dual-boot repo if it doesn't), then `journalctl -u ollama | grep -i gpu`.
Reinstalling after the driver (`curl -fsSL https://ollama.com/install.sh | sh`)
rebinds GPU support, then `sudo systemctl restart ollama`.
