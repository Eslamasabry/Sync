#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_DIR="$ROOT_DIR/.run"
STOP_HOST_INFRA=0
STOP_DOCKER_INFRA=0

usage() {
  cat <<'EOF'
Usage: scripts/local/stop_services.sh [options]

Stops the local API and worker started by scripts/local/start_services.sh.

Options:
  --stop-host-infra     Also stop host PostgreSQL and Redis services
  --stop-docker-infra   Also run docker compose down
EOF
}

stop_pid_file() {
  local pid_file="$1"
  if [[ ! -f "$pid_file" ]]; then
    return 0
  fi

  local pid
  pid="$(cat "$pid_file")"
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid"
    for _ in {1..20}; do
      if ! kill -0 "$pid" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  fi
  rm -f "$pid_file"
}

cleanup_stale_pid_file() {
  local pid_file="$1"
  if [[ ! -f "$pid_file" ]]; then
    return 0
  fi
  local pid
  pid="$(cat "$pid_file")"
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    rm -f "$pid_file"
  fi
}

while (($# > 0)); do
  case "$1" in
    --stop-host-infra)
      STOP_HOST_INFRA=1
      shift
      ;;
    --stop-docker-infra)
      STOP_DOCKER_INFRA=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

cleanup_stale_pid_file "$RUN_DIR/backend-api.pid"
cleanup_stale_pid_file "$RUN_DIR/backend-worker.pid"
stop_pid_file "$RUN_DIR/backend-api.pid"
stop_pid_file "$RUN_DIR/backend-worker.pid"

if [[ "$STOP_DOCKER_INFRA" -eq 1 ]]; then
  (
    cd "$ROOT_DIR"
    docker compose down
  )
fi

if [[ "$STOP_HOST_INFRA" -eq 1 ]]; then
  sudo systemctl stop redis-server postgresql
fi

echo "Stopped local backend services."
