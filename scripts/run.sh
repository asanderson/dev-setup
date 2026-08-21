#!/usr/bin/env bash
# run.sh — run a dev-setup container image (built by scripts/build.sh) in
# Docker (default) or Podman.
#
#   Interactive:   ./scripts/run.sh
#   Unattended:    DEV_SETUP_ASSUME_YES=1 ./scripts/run.sh [--user NAME|UID[:GID]]
#                    [--mount DIR ...] [--engine docker|podman] [--image TAG]
#                    [-- CMD ...]
#
# Prompts (or takes flags) for which user to run the container as — the
# user who executed this script is the default — and which local
# directories to mount into the container (each DIR appears at the same
# path inside). Anything after `--` runs instead of the default login
# shell.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  echo "Usage: $0 [--engine docker|podman] [--image TAG] [--user NAME|UID[:GID]]"
  echo "          [--mount DIR ...] [--mounts DIR1,DIR2,...] [-- CMD ...]"
  echo "  --engine   docker (default) or podman"
  echo "  --image    image tag to run (default: dev-setup:latest)"
  echo "  --user     user to run as: a local user name or UID[:GID]"
  echo "             (default: the user executing this script)"
  echo "  --mount    local directory to mount at the same path inside the"
  echo "             container; repeatable (--mounts takes a comma list)"
  echo "  -- CMD     run CMD instead of the default login shell"
  echo "Without flags (and without DEV_SETUP_ASSUME_YES=1) the user and"
  echo "mounts are prompted for interactively."
}

ENGINE="docker"
IMAGE="dev-setup:latest"
RUN_USER=""
MOUNTS=()
CMD=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine)
      ENGINE="${2:?--engine needs docker or podman}"
      [[ "$ENGINE" == docker || "$ENGINE" == podman ]] \
        || { err "--engine must be docker or podman"; exit 2; }
      shift ;;
    --image) IMAGE="${2:?--image needs a tag}"; shift ;;
    --user)  RUN_USER="${2:?--user needs a name or UID[:GID]}"; shift ;;
    --mount) MOUNTS+=("${2:?--mount needs a directory}"); shift ;;
    --mounts)
      IFS=, read -ra _dirs <<<"${2:?--mounts needs a comma-separated list}"
      MOUNTS+=("${_dirs[@]}")
      shift ;;
    --) shift; CMD=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown argument: $1"; usage; exit 2 ;;
  esac
  shift
done

command_exists "$ENGINE" || die "${ENGINE} not found — install it (or pass the other --engine)."

# --- Which user to run as (default: whoever executed this script) --------
DEFAULT_USER="$(id -un)"
if [[ -z "$RUN_USER" ]]; then
  if [[ "${DEV_SETUP_ASSUME_YES:-0}" == "1" ]]; then
    RUN_USER="$DEFAULT_USER"
  else
    read -r -p "Run the container as which user? [${DEFAULT_USER}] " RUN_USER \
      || RUN_USER=""
    [[ -z "$RUN_USER" ]] && RUN_USER="$DEFAULT_USER"
  fi
fi

# Resolve to uid:gid — a local user name, a UID[:GID], or 'dev' (the
# image's built-in user, uid 1000 by build.sh's contract).
if [[ "$RUN_USER" =~ ^[0-9]+(:[0-9]+)?$ ]]; then
  UIDGID="$RUN_USER"
  [[ "$UIDGID" == *:* ]] || UIDGID="${UIDGID}:${UIDGID}"
elif id -u "$RUN_USER" >/dev/null 2>&1; then
  UIDGID="$(id -u "$RUN_USER"):$(id -g "$RUN_USER")"
elif [[ "$RUN_USER" == dev ]]; then
  UIDGID="1000:1000"
else
  die "User '${RUN_USER}' not found locally — pass a UID[:GID] instead."
fi

# --- Which local directories to mount ------------------------------------
if [[ ${#MOUNTS[@]} -eq 0 && "${DEV_SETUP_ASSUME_YES:-0}" != "1" ]]; then
  read -r -p "Local directories to mount (comma-separated, empty for none): " _ans \
    || _ans=""
  if [[ -n "$_ans" ]]; then
    IFS=, read -ra MOUNTS <<<"$_ans"
  fi
fi

VOLUMES=()
for dir in ${MOUNTS[@]+"${MOUNTS[@]}"}; do
  # Trim whitespace and normalize to an absolute path.
  dir="${dir#"${dir%%[![:space:]]*}"}"; dir="${dir%"${dir##*[![:space:]]}"}"
  [[ -n "$dir" ]] || continue
  [[ -d "$dir" ]] || die "Mount directory not found: ${dir}"
  dir="$(cd "$dir" && pwd)"
  VOLUMES+=(-v "${dir}:${dir}")
done

# --- Run -----------------------------------------------------------------
# The image's only regular user is 'dev' (uid 1000): running as uid 1000
# keeps its home and PATH; any other uid gets a writable HOME in /tmp.
if [[ "${UIDGID%%:*}" == "1000" ]]; then
  HOME_IN_CONTAINER="/home/dev"
else
  HOME_IN_CONTAINER="/tmp"
fi

TI=(-i)
[[ -t 0 && -t 1 ]] && TI=(-i -t)

# Status to stderr: the container's stdout is the deliverable (callers
# capture it), so keep it clean.
log "Running ${IMAGE} with ${ENGINE} as ${RUN_USER} (${UIDGID})" >&2
if [[ ${#VOLUMES[@]} -gt 0 ]]; then
  log "Mounts: ${MOUNTS[*]}" >&2
fi

exec "$ENGINE" run --rm "${TI[@]}" \
  --user "$UIDGID" \
  -e "HOME=${HOME_IN_CONTAINER}" \
  ${VOLUMES[@]+"${VOLUMES[@]}"} \
  "$IMAGE" \
  ${CMD[@]+"${CMD[@]}"}
