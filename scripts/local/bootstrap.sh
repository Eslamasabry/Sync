#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROVIDER="static"
SKIP_FLUTTER=0

usage() {
  cat <<'EOF'
Usage: scripts/local/bootstrap.sh [--provider static|whisperx] [--skip-flutter]

Prepares the local development environment for Sync:
  - ensures backend/.env exists
  - sets the transcriber provider
  - starts docker-compose infrastructure
  - installs backend dependencies
  - runs flutter pub get

Examples:
  scripts/local/bootstrap.sh
  scripts/local/bootstrap.sh --provider whisperx
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

require_cmd docker
require_cmd python3
require_cmd flutter

mkdir -p "$ROOT_DIR/backend"
if [[ ! -f "$ROOT_DIR/backend/.env" ]]; then
  cp "$ROOT_DIR/backend/.env.example" "$ROOT_DIR/backend/.env"
fi

update_env_value "TRANSCRIBER_PROVIDER" "$PROVIDER"
if [[ "$PROVIDER" == "static" ]]; then
  update_env_value "MOCK_TRANSCRIPT_TEXT" "call me ishmael"
fi

(
  cd "$ROOT_DIR"
  docker compose up -d
)

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
Next:
  scripts/local/start_services.sh
  scripts/local/run_smoke.sh --provider $PROVIDER
EOF
