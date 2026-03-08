#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROVIDER="static"

usage() {
  cat <<'EOF'
Usage: scripts/local/full_smoke.sh [--provider static|whisperx]

Runs the complete local smoke flow:
  1. bootstrap infrastructure and dependencies
  2. start backend API and worker
  3. generate sample assets and run an alignment job
EOF
}

while (($# > 0)); do
  case "$1" in
    --provider)
      PROVIDER="${2:-}"
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

"$ROOT_DIR/scripts/local/bootstrap.sh" --provider "$PROVIDER"
"$ROOT_DIR/scripts/local/start_services.sh"
"$ROOT_DIR/scripts/local/run_smoke.sh" --provider "$PROVIDER"
