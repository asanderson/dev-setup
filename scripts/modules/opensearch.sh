# shellcheck shell=bash
# Module: OpenSearch Platform (OpenSearch + Dashboards) — Apache-2.0,
# containerized. The no-license-tiers alternative to the Elastic Stack module
# (steward: OpenSearch Software Foundation / Linux Foundation). Uses
# config/opensearch/docker-compose.yml; state lives in a named Docker volume.
# Ports are offset (9201/5602) so it can run beside the Elastic stack.

module_opensearch_describe() { echo "OpenSearch Platform ${OPENSEARCH_VERSION} in Docker (Apache-2.0, OpenSearch + Dashboards; Elastic alternative)"; }

module_opensearch_install() {
  section "OpenSearch Platform ${OPENSEARCH_VERSION} (Docker, Apache-2.0)"

  if ! command_exists docker; then
    err "Docker Engine + Compose plugin required. Select the Docker module first."
    return 1
  fi

  # Fresh 'docker' group membership doesn't apply to the current session, so a
  # docker+opensearch run in one pass would fail on the socket. Fall back to
  # sudo for this run; plain 'docker' works after the next login.
  local -a D=(docker)
  if ! docker info >/dev/null 2>&1; then
    if sudo docker info >/dev/null 2>&1; then
      warn "Docker socket not accessible as $USER yet (new group membership needs a re-login);"
      warn "using 'sudo docker' for this run. After logging out/in, plain 'docker' works."
      D=(sudo docker)
    else
      err "Docker daemon not reachable (even via sudo). Is the service running?"
      return 1
    fi
  fi
  if ! "${D[@]}" compose version >/dev/null 2>&1; then
    err "Docker Compose plugin missing. Select the Docker module first."
    return 1
  fi

  local src_dir="${REPO_ROOT}/config/opensearch"
  local dest_dir="${OPENSEARCH_HOME:-$HOME/opensearch}"
  mkdir -p "$dest_dir"
  cp "$src_dir/docker-compose.yml" "$dest_dir/"

  # OpenSearch requires vm.max_map_count >= 262144 (same as Elasticsearch).
  if [[ "$(sysctl -n vm.max_map_count)" -lt 262144 ]]; then
    log "Raising vm.max_map_count to 262144 (persisted in /etc/sysctl.d/99-opensearch.conf)."
    echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-opensearch.conf >/dev/null
    sudo sysctl --system >/dev/null
  fi

  # Seed .env with a generated admin password on first run. The image rejects
  # weak passwords (min 8 chars, upper+lower+digit+special, zxcvbn-strong)
  # and exits, so the fixed 'Aa1!' tail guarantees every character class on
  # top of ~24 random chars.
  if [[ ! -f "$dest_dir/.env" ]]; then
    local admin_pw
    admin_pw="$(openssl rand -base64 18 | tr -d '/+=')Aa1!"
    cat > "$dest_dir/.env" <<EOF
OPENSEARCH_VERSION=${OPENSEARCH_VERSION}
OPENSEARCH_ADMIN_PASSWORD=${admin_pw}
OPENSEARCH_HEAP=2g
EOF
    chmod 600 "$dest_dir/.env"
    ok "Generated credentials in $dest_dir/.env (not echoed here — read the file when you need them)."
  else
    log "Keeping existing $dest_dir/.env."
  fi

  log "Starting OpenSearch (first pull downloads ~1GB of images)..."
  ( cd "$dest_dir" && "${D[@]}" compose up -d opensearch )

  log "Waiting for OpenSearch to become healthy..."
  local i
  for i in $(seq 1 60); do
    if [[ "$("${D[@]}" inspect -f '{{.State.Health.Status}}' opensearch 2>/dev/null)" == "healthy" ]]; then
      break
    fi
    sleep 5
    [[ "$i" == "60" ]] && { err "OpenSearch did not become healthy; see 'docker logs opensearch'."; return 1; }
  done

  # No service-user password step (unlike Elastic's kibana_system): the demo
  # security config already provisions the kibanaserver user Dashboards uses.
  ( cd "$dest_dir" && "${D[@]}" compose up -d )

  ok "OpenSearch Platform is starting."
  log "  OpenSearch: https://localhost:9201  (user: admin, password in $dest_dir/.env;"
  log "              self-signed demo cert, so: curl -k -u admin:<pw> https://localhost:9201)"
  log "  Dashboards: http://localhost:5602   (same credentials; may take ~1 min to come up)"
  log "  Both bind to localhost only; ports offset so the Elastic stack (9200/5601) can coexist."
  log "  Manage:     cd $dest_dir && docker compose [stop|start|down|logs -f]"
}

module_opensearch_uninstall() {
  section "Uninstall: OpenSearch Platform"
  local dest="${OPENSEARCH_HOME:-$HOME/opensearch}"
  local -a D=(docker)
  docker info >/dev/null 2>&1 || D=(sudo docker)
  if [[ -f "$dest/docker-compose.yml" ]]; then
    if [[ "${PURGE_DATA:-0}" == "1" ]]; then
      ( cd "$dest" && "${D[@]}" compose down -v ) 2>/dev/null || true
      rm -rf "$dest"
      "${D[@]}" rmi "opensearchproject/opensearch:${OPENSEARCH_VERSION}" \
        "opensearchproject/opensearch-dashboards:${OPENSEARCH_VERSION}" 2>/dev/null || true
      log "Purged the stack, its data volume, ${dest}, and the images."
    else
      ( cd "$dest" && "${D[@]}" compose down ) 2>/dev/null || true
      log "Containers stopped and removed. Kept: the data volume, ${dest}/.env, and the images (--purge-data removes them)."
    fi
  else
    log "No stack found at ${dest} — nothing to do."
  fi
}
