# shellcheck shell=bash
# Module: Elastic Stack (Elasticsearch + Kibana) — Basic license, containerized.
# Uses config/elastic/docker-compose.yml; state lives in a named Docker volume.

module_elastic_describe() { echo "Elastic Stack ${ELASTIC_VERSION} in Docker (Basic license, ES + Kibana)"; }

module_elastic_install() {
  section "Elastic Stack ${ELASTIC_VERSION} (Docker, Basic license)"

  if ! command_exists docker; then
    err "Docker Engine + Compose plugin required. Select the Docker module first."
    return 1
  fi

  # Fresh 'docker' group membership doesn't apply to the current session, so a
  # docker+elastic run in one pass would fail on the socket. Fall back to sudo
  # for this run; plain 'docker' works after the next login.
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

  local src_dir="${REPO_ROOT}/config/elastic"
  local dest_dir="${ELASTIC_HOME:-$HOME/elastic}"
  mkdir -p "$dest_dir"
  cp "$src_dir/docker-compose.yml" "$dest_dir/"

  # Elasticsearch requires vm.max_map_count >= 262144.
  if [[ "$(sysctl -n vm.max_map_count)" -lt 262144 ]]; then
    log "Raising vm.max_map_count to 262144 (persisted in /etc/sysctl.d/99-elastic.conf)."
    echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-elastic.conf >/dev/null
    sudo sysctl --system >/dev/null
  fi

  # Seed .env with generated passwords on first run.
  if [[ ! -f "$dest_dir/.env" ]]; then
    local es_pw kb_pw
    es_pw="$(openssl rand -base64 18 | tr -d '/+=')"
    kb_pw="$(openssl rand -base64 18 | tr -d '/+=')"
    cat > "$dest_dir/.env" <<EOF
ELASTIC_VERSION=${ELASTIC_VERSION}
ELASTIC_PASSWORD=${es_pw}
KIBANA_PASSWORD=${kb_pw}
ES_HEAP=2g
EOF
    chmod 600 "$dest_dir/.env"
    ok "Generated credentials in $dest_dir/.env (not echoed here — read the file when you need them)."
  else
    log "Keeping existing $dest_dir/.env."
  fi

  # shellcheck disable=SC1091
  source "$dest_dir/.env"

  log "Starting Elasticsearch (first pull downloads ~1.5GB of images)..."
  ( cd "$dest_dir" && "${D[@]}" compose up -d elasticsearch )

  log "Waiting for Elasticsearch to become healthy..."
  local i
  for i in $(seq 1 60); do
    if [[ "$("${D[@]}" inspect -f '{{.State.Health.Status}}' elasticsearch 2>/dev/null)" == "healthy" ]]; then
      break
    fi
    sleep 5
    [[ "$i" == "60" ]] && { err "Elasticsearch did not become healthy; see 'docker logs elasticsearch'."; return 1; }
  done

  # Set the kibana_system password so Kibana can authenticate. -f makes curl
  # fail on HTTP errors so a bad request or auth failure fails this module
  # loudly instead of leaving Kibana unable to log in. (The HTTP layer is
  # plain http on 127.0.0.1 — see the note in docker-compose.yml.)
  if ! "${D[@]}" exec elasticsearch bash -c \
    "curl -sf -X POST -u 'elastic:${ELASTIC_PASSWORD}' \
     -H 'Content-Type: application/json' \
     http://localhost:9200/_security/user/kibana_system/_password \
     -d '{\"password\":\"${KIBANA_PASSWORD}\"}'" >/dev/null; then
    err "Failed to set the kibana_system password — Kibana logins would fail."
    err "Check 'docker logs elasticsearch', then re-run this module."
    return 1
  fi

  ( cd "$dest_dir" && "${D[@]}" compose up -d )

  ok "Elastic Stack is starting."
  log "  Elasticsearch: http://localhost:9200  (user: elastic, password in $dest_dir/.env; localhost-only)"
  log "  Kibana:        http://localhost:5601   (same credentials; may take ~1 min to come up)"
  log "  License check: curl -s -u elastic:<pw> http://localhost:9200/_license"
  log "  Manage:        cd $dest_dir && docker compose [stop|start|down|logs -f]"
}

module_elastic_uninstall() {
  section "Uninstall: Elastic Stack"
  local dest="${ELASTIC_HOME:-$HOME/elastic}"
  local -a D=(docker)
  docker info >/dev/null 2>&1 || D=(sudo docker)
  if [[ -f "$dest/docker-compose.yml" ]]; then
    if [[ "${PURGE_DATA:-0}" == "1" ]]; then
      ( cd "$dest" && "${D[@]}" compose down -v ) 2>/dev/null || true
      rm -rf "$dest"
      "${D[@]}" rmi "docker.elastic.co/elasticsearch/elasticsearch:${ELASTIC_VERSION}" \
        "docker.elastic.co/kibana/kibana:${ELASTIC_VERSION}" 2>/dev/null || true
      log "Purged the stack, its data volume, ${dest}, and the images."
    else
      ( cd "$dest" && "${D[@]}" compose down ) 2>/dev/null || true
      log "Containers stopped and removed. Kept: the data volume, ${dest}/.env, and the images (--purge-data removes them)."
    fi
  else
    log "No stack found at ${dest} — nothing to do."
  fi
}
