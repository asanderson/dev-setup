# shellcheck shell=bash
# Module: Elastic Stack (Elasticsearch + Kibana) — Basic license, containerized.
# Uses config/elastic/docker-compose.yml; state lives in a named Docker volume.

module_elastic_describe() { echo "Elastic Stack ${ELASTIC_VERSION} in Docker (Basic license, ES + Kibana)"; }

module_elastic_install() {
  section "Elastic Stack ${ELASTIC_VERSION} (Docker, Basic license)"

  if ! command_exists docker || ! docker compose version >/dev/null 2>&1; then
    err "Docker Engine + Compose plugin required. Select the Docker module first."
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
    ok "Generated credentials in $dest_dir/.env (elastic password: ${es_pw})"
  else
    log "Keeping existing $dest_dir/.env."
  fi

  # shellcheck disable=SC1091
  source "$dest_dir/.env"

  log "Starting Elasticsearch (first pull downloads ~1.5GB of images)..."
  ( cd "$dest_dir" && docker compose up -d elasticsearch )

  log "Waiting for Elasticsearch to become healthy..."
  local i
  for i in $(seq 1 60); do
    if [[ "$(docker inspect -f '{{.State.Health.Status}}' elasticsearch 2>/dev/null)" == "healthy" ]]; then
      break
    fi
    sleep 5
    [[ "$i" == "60" ]] && { err "Elasticsearch did not become healthy; see 'docker logs elasticsearch'."; return 1; }
  done

  # Set the kibana_system password so Kibana can authenticate.
  docker exec elasticsearch bash -c \
    "curl -s -X POST --cacert config/certs/http_ca.crt -u 'elastic:${ELASTIC_PASSWORD}' \
     -H 'Content-Type: application/json' \
     https://localhost:9200/_security/user/kibana_system/_password \
     -d '{\"password\":\"${KIBANA_PASSWORD}\"}' \
     || curl -s -X POST -u 'elastic:${ELASTIC_PASSWORD}' \
     -H 'Content-Type: application/json' \
     http://localhost:9200/_security/user/kibana_system/_password \
     -d '{\"password\":\"${KIBANA_PASSWORD}\"}'" >/dev/null || true

  ( cd "$dest_dir" && docker compose up -d )

  ok "Elastic Stack is starting."
  log "  Elasticsearch: https://localhost:9200  (user: elastic, password in $dest_dir/.env)"
  log "  Kibana:        http://localhost:5601   (same credentials; may take ~1 min to come up)"
  log "  License check: docker exec elasticsearch curl -sk -u elastic:<pw> https://localhost:9200/_license"
  log "  Manage:        cd $dest_dir && docker compose [stop|start|down|logs -f]"
}
