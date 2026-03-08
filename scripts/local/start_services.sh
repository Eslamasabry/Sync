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

is_running() {
  local pid_file="$1"
  if [[ ! -f "$pid_file" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "$pid_file")"
  kill -0 "$pid" >/dev/null 2>&1
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

if is_running "$API_PID_FILE"; then
  echo "API already running with pid $(cat "$API_PID_FILE")"
else
  (
    cd "$ROOT_DIR/backend"
    nohup .venv/bin/uvicorn sync_backend.main:app --host "$HOST" --port "$PORT" \
      >"$API_LOG" 2>&1 &
    echo $! >"$API_PID_FILE"
  )
fi

if is_running "$WORKER_PID_FILE"; then
  echo "Worker already running with pid $(cat "$WORKER_PID_FILE")"
else
  (
    cd "$ROOT_DIR/backend"
    nohup .venv/bin/celery -A sync_backend.workers.celery_app:celery_app worker --loglevel=info \
      >"$WORKER_LOG" 2>&1 &
    echo $! >"$WORKER_PID_FILE"
  )
fi

if ! wait_for_health "$READY_URL"; then
  echo "API did not become ready. Check $API_LOG and $WORKER_LOG" >&2
  if [[ "$TAIL_ON_FAILURE" -eq 1 ]]; then
    print_log_tail "$API_LOG"
    print_log_tail "$WORKER_LOG"
  fi
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
