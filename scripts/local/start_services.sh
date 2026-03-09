#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_DIR="$ROOT_DIR/.run"
API_LOG="$RUN_DIR/backend-api.log"
WORKER_LOG="$RUN_DIR/backend-worker.log"
API_PID_FILE="$RUN_DIR/backend-api.pid"
WORKER_PID_FILE="$RUN_DIR/backend-worker.pid"
HOST="127.0.0.1"
PORT="8000"
READY_URL=""
TAIL_ON_FAILURE=1

usage() {
  cat <<'EOF'
Usage: scripts/local/start_services.sh [options]

Starts the backend API and Celery worker in the background and stores:
  - logs under .run/
  - pid files under .run/

Options:
  --host HOST              Bind host. Default: 127.0.0.1
  --port PORT              Bind port. Default: 8000
  --ready-url URL          Readiness URL. Default: http://HOST:PORT/v1/ready
  --no-tail-on-failure     Do not print log tails when startup fails
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

read_pid() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 1
  cat "$pid_file"
}

is_running() {
  local pid_file="$1"
  local pid
  pid="$(read_pid "$pid_file")" || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

cleanup_stale_pid_file() {
  local pid_file="$1"
  if is_running "$pid_file"; then
    return 0
  fi
  if [[ -f "$pid_file" ]]; then
    rm -f "$pid_file"
  fi
}

process_matches() {
  local pid_file="$1"
  local pattern="$2"
  local pid
  pid="$(read_pid "$pid_file")" || return 1
  ps -p "$pid" -o args= 2>/dev/null | grep -F "$pattern" >/dev/null 2>&1
}

start_background_process() {
  local pid_file="$1"
  local log_file="$2"
  shift 2
  local command=("$@")

  cleanup_stale_pid_file "$pid_file"
  if is_running "$pid_file"; then
    return 1
  fi

  (
    cd "$ROOT_DIR/backend"
    nohup "${command[@]}" </dev/null >"$log_file" 2>&1 &
    echo $! >"$pid_file"
  )
}

wait_for_health() {
  local url="$1"
  for _ in {1..60}; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

print_log_tail() {
  local path="$1"
  if [[ -f "$path" ]]; then
    echo "--- tail: $path ---" >&2
    tail -n 40 "$path" >&2 || true
  fi
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
    --ready-url)
      READY_URL="${2:-}"
      shift 2
      ;;
    --no-tail-on-failure)
      TAIL_ON_FAILURE=0
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

require_cmd curl

if [[ ! -x "$ROOT_DIR/backend/.venv/bin/uvicorn" ]]; then
  echo "Backend virtualenv is missing. Run scripts/local/bootstrap.sh first." >&2
  exit 1
fi

mkdir -p "$RUN_DIR"
if [[ -z "$READY_URL" ]]; then
  READY_URL="http://$HOST:$PORT/v1/ready"
fi

cleanup_stale_pid_file "$API_PID_FILE"
cleanup_stale_pid_file "$WORKER_PID_FILE"

if is_running "$API_PID_FILE"; then
  echo "API already running with pid $(cat "$API_PID_FILE")"
else
  start_background_process \
    "$API_PID_FILE" \
    "$API_LOG" \
    .venv/bin/uvicorn sync_backend.main:app --host "$HOST" --port "$PORT"
fi

if is_running "$WORKER_PID_FILE"; then
  echo "Worker already running with pid $(cat "$WORKER_PID_FILE")"
else
  start_background_process \
    "$WORKER_PID_FILE" \
    "$WORKER_LOG" \
    .venv/bin/celery -A sync_backend.workers.celery_app:celery_app worker --loglevel=info
fi

if ! wait_for_health "$READY_URL"; then
  echo "API did not become ready. Check $API_LOG and $WORKER_LOG" >&2
  if [[ "$TAIL_ON_FAILURE" -eq 1 ]]; then
    print_log_tail "$API_LOG"
    print_log_tail "$WORKER_LOG"
  fi
  exit 1
fi

if ! process_matches "$API_PID_FILE" "uvicorn sync_backend.main:app"; then
  echo "API process did not remain attached to the expected uvicorn command." >&2
  print_log_tail "$API_LOG"
  exit 1
fi

if ! process_matches "$WORKER_PID_FILE" "celery -A sync_backend.workers.celery_app:celery_app worker"; then
  echo "Worker process did not remain attached to the expected celery command." >&2
  print_log_tail "$WORKER_LOG"
  exit 1
fi

cat <<EOF
Services started.

API:
  pid: $(cat "$API_PID_FILE")
  log: $API_LOG

Worker:
  pid: $(cat "$WORKER_PID_FILE")
  log: $WORKER_LOG

Ready URL:
  $READY_URL
EOF
