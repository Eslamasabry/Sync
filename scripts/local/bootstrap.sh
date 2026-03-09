#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROVIDER="static"
SKIP_FLUTTER=0
INFRA_MODE="auto"
EXECUTION_MODE="celery"
DATABASE_MODE="postgres"

usage() {
  cat <<'EOF'
Usage: scripts/local/bootstrap.sh [--provider static|whisperx] [--skip-flutter] [--infra auto|host|docker|none] [--execution-mode celery|inline] [--database postgres|sqlite] [--lite]

Prepares the local development environment for Sync:
  - ensures backend/.env exists
  - sets the transcriber provider
  - optionally starts infrastructure
  - installs backend dependencies
  - runs flutter pub get

Examples:
  scripts/local/bootstrap.sh
  scripts/local/bootstrap.sh --provider whisperx
  scripts/local/bootstrap.sh --infra host
  scripts/local/bootstrap.sh --lite
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

update_env_value() {
  local key="$1"
  local value="$2"
  python3 - "$ROOT_DIR/backend/.env" "$key" "$value" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]

if path.exists():
    lines = path.read_text().splitlines()
else:
    lines = []

for index, line in enumerate(lines):
    if line.startswith(f"{key}="):
        lines[index] = f"{key}={value}"
        break
else:
    lines.append(f"{key}={value}")

path.write_text("\n".join(lines) + "\n")
PY
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

host_infra_ready() {
  if ! have_cmd pg_isready || ! have_cmd redis-cli; then
    return 1
  fi

  pg_isready -h localhost -p 5432 >/dev/null 2>&1 &&
    [[ "$(redis-cli ping 2>/dev/null)" == "PONG" ]]
}

start_infra() {
  case "$INFRA_MODE" in
    docker)
      require_cmd docker
      (
        cd "$ROOT_DIR"
        docker compose up -d
      )
      ;;
    host)
      if ! host_infra_ready; then
        cat >&2 <<'EOF'
Host infrastructure is not ready.

Expected:
  - PostgreSQL reachable on localhost:5432
  - Redis reachable on localhost:6379

If you installed them with apt:
  sudo systemctl start postgresql redis-server
EOF
        exit 1
      fi
      ;;
    none)
      ;;
    auto)
      if host_infra_ready; then
        echo "Using host PostgreSQL and Redis."
      else
        require_cmd docker
        (
          cd "$ROOT_DIR"
          docker compose up -d
        )
      fi
      ;;
    *)
      echo "Unsupported infra mode: $INFRA_MODE" >&2
      exit 1
      ;;
  esac
}

while (($# > 0)); do
  case "$1" in
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --skip-flutter)
      SKIP_FLUTTER=1
      shift
      ;;
    --infra)
      INFRA_MODE="${2:-}"
      shift 2
      ;;
    --execution-mode)
      EXECUTION_MODE="${2:-}"
      shift 2
      ;;
    --database)
      DATABASE_MODE="${2:-}"
      shift 2
      ;;
    --lite)
      EXECUTION_MODE="inline"
      DATABASE_MODE="sqlite"
      INFRA_MODE="none"
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

if [[ "$PROVIDER" != "static" && "$PROVIDER" != "whisperx" ]]; then
  echo "Unsupported provider: $PROVIDER" >&2
  exit 1
fi
if [[ "$EXECUTION_MODE" != "celery" && "$EXECUTION_MODE" != "inline" ]]; then
  echo "Unsupported execution mode: $EXECUTION_MODE" >&2
  exit 1
fi
if [[ "$DATABASE_MODE" != "postgres" && "$DATABASE_MODE" != "sqlite" ]]; then
  echo "Unsupported database mode: $DATABASE_MODE" >&2
  exit 1
fi

require_cmd python3
if [[ "$SKIP_FLUTTER" -eq 0 ]]; then
  require_cmd flutter
fi

mkdir -p "$ROOT_DIR/backend"
if [[ ! -f "$ROOT_DIR/backend/.env" ]]; then
  cp "$ROOT_DIR/backend/.env.example" "$ROOT_DIR/backend/.env"
fi

update_env_value "TRANSCRIBER_PROVIDER" "$PROVIDER"
update_env_value "JOB_EXECUTION_MODE" "$EXECUTION_MODE"
if [[ "$DATABASE_MODE" == "sqlite" ]]; then
  mkdir -p "$ROOT_DIR/backend/artifacts"
  update_env_value "DATABASE_URL" "sqlite+pysqlite:///$ROOT_DIR/backend/artifacts/sync-lite.db"
else
  update_env_value "DATABASE_URL" "postgresql+psycopg://sync:sync@localhost:5432/sync"
fi
if [[ "$PROVIDER" == "static" ]]; then
  update_env_value "MOCK_TRANSCRIPT_TEXT" "call me ishmael"
fi

start_infra

(
  cd "$ROOT_DIR/backend"
  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip setuptools wheel
  if [[ "$PROVIDER" == "whisperx" ]]; then
    .venv/bin/pip install -e '.[alignment,dev]'
  else
    .venv/bin/pip install -e '.[dev]' imageio-ffmpeg mutagen
  fi
)

if [[ "$SKIP_FLUTTER" -eq 0 ]]; then
  (
    cd "$ROOT_DIR/flutter_app"
    flutter pub get
  )
fi

cat <<EOF
Bootstrap complete.

Provider: $PROVIDER
Infra mode: $INFRA_MODE
Execution mode: $EXECUTION_MODE
Database mode: $DATABASE_MODE
Next:
  scripts/local/start_services.sh
  scripts/local/run_smoke.sh --provider $PROVIDER
EOF
