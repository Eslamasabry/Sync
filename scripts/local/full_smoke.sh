#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROVIDER="static"
INFRA_MODE="auto"
KEEP_RUNNING=0

usage() {
  cat <<'EOF'
Usage: scripts/local/full_smoke.sh [options]

Runs the complete local smoke flow:
  1. bootstrap infrastructure and dependencies
  2. start backend API and worker
  3. generate sample assets and run an alignment job

Options:
  --provider static|whisperx   Transcriber provider. Default: static
  --infra auto|host|docker|none
                               Infrastructure mode passed to bootstrap.
  --keep-running               Leave API and worker running after the smoke run
EOF
}

cleanup() {
  if [[ "$KEEP_RUNNING" -eq 0 ]]; then
    "$ROOT_DIR/scripts/local/stop_services.sh"
  fi
}

while (($# > 0)); do
  case "$1" in
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --infra)
      INFRA_MODE="${2:-}"
      shift 2
      ;;
    --keep-running)
      KEEP_RUNNING=1
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

trap cleanup EXIT

"$ROOT_DIR/scripts/local/bootstrap.sh" --provider "$PROVIDER" --infra "$INFRA_MODE"
"$ROOT_DIR/scripts/local/start_services.sh"
"$ROOT_DIR/scripts/local/run_smoke.sh" --provider "$PROVIDER"
