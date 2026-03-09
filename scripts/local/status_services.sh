#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_DIR="$ROOT_DIR/.run"
HOST="127.0.0.1"
PORT="8000"

usage() {
  cat <<'EOF'
Usage: scripts/local/status_services.sh [--host HOST] [--port PORT]

Prints PID, log path, and API readiness status for the locally started services.
EOF
}

is_running() {
  local pid_file="$1"
  if [[ ! -f "$pid_file" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "$pid_file")"
  kill -0 "$pid" >/dev/null 2>&1
}

read_pid() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 1
  cat "$pid_file"
}

while (($# > 0)); do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
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

for service in backend-api backend-worker; do
  pid_file="$RUN_DIR/$service.pid"
  log_file="$RUN_DIR/$service.log"
  if is_running "$pid_file"; then
    echo "$service: running pid=$(cat "$pid_file") log=$log_file"
  elif [[ -f "$pid_file" ]]; then
    echo "$service: stale pid=$(read_pid "$pid_file") log=$log_file"
  else
    echo "$service: stopped"
  fi
done

if command -v curl >/dev/null 2>&1 && curl -fsS "http://$HOST:$PORT/v1/ready" >/dev/null 2>&1; then
  echo "api_ready: yes"
else
  echo "api_ready: no"
fi
