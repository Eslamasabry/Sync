#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_BASE_URL="http://127.0.0.1:8000/v1"
OUTPUT_DIR="$ROOT_DIR/tmp/smoke"
PROJECT_TITLE="Local Demo"
TEXT="Call me Ishmael."
PROVIDER="static"
WAIT_SECONDS=120
POLL_SECONDS=1

usage() {
  cat <<'EOF'
Usage: scripts/local/run_smoke.sh [options]

Creates a sample project, uploads generated EPUB/audio, creates an alignment job,
waits for completion, and saves reader-model and sync artifacts.

Options:
  --api-base-url URL       Backend API base URL. Default: http://127.0.0.1:8000/v1
  --output-dir PATH        Output directory for generated assets and fetched artifacts.
  --project-title TITLE    Project title to create.
  --text TEXT              Text to place in the generated EPUB.
  --provider NAME          Provider hint printed in the summary.
  --wait-seconds N         Maximum seconds to wait for completion. Default: 120
  --poll-seconds N         Poll interval in seconds. Default: 1
EOF
}

extract_json_field() {
  local field="$1"
  python3 -c '
import json
import sys

payload = json.load(sys.stdin)
value = payload[sys.argv[1]]
if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
' "$field"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

while (($# > 0)); do
  case "$1" in
    --api-base-url)
      API_BASE_URL="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --project-title)
      PROJECT_TITLE="${2:-}"
      shift 2
      ;;
    --text)
      TEXT="${2:-}"
      shift 2
      ;;
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --wait-seconds)
      WAIT_SECONDS="${2:-}"
      shift 2
      ;;
    --poll-seconds)
      POLL_SECONDS="${2:-}"
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

require_cmd curl
require_cmd python3

mkdir -p "$OUTPUT_DIR"

if ! curl -fsS "$API_BASE_URL/ready" >/dev/null; then
  echo "Backend is not ready at $API_BASE_URL/ready" >&2
  exit 1
fi

mapfile -t GENERATED_PATHS < <(
  python3 "$ROOT_DIR/scripts/local/generate_smoke_assets.py" \
    --output-dir "$OUTPUT_DIR" \
    --title "$PROJECT_TITLE" \
    --text "$TEXT"
)

EPUB_PATH="${GENERATED_PATHS[0]}"
AUDIO_PATH="${GENERATED_PATHS[1]}"

PROJECT_JSON="$(curl -fsS -X POST "$API_BASE_URL/projects" \
  -H 'content-type: application/json' \
  -d "{\"title\":\"$PROJECT_TITLE\",\"language\":\"en\"}")"
PROJECT_ID="$(printf '%s' "$PROJECT_JSON" | extract_json_field project_id)"

EPUB_JSON="$(curl -fsS -X POST "$API_BASE_URL/projects/$PROJECT_ID/assets/upload" \
  -F kind=epub \
  -F "file=@$EPUB_PATH")"
EPUB_ASSET_ID="$(printf '%s' "$EPUB_JSON" | extract_json_field asset_id)"

AUDIO_JSON="$(curl -fsS -X POST "$API_BASE_URL/projects/$PROJECT_ID/assets/upload" \
  -F kind=audio \
  -F "file=@$AUDIO_PATH")"
AUDIO_ASSET_ID="$(printf '%s' "$AUDIO_JSON" | extract_json_field asset_id)"

JOB_JSON="$(curl -fsS -X POST "$API_BASE_URL/projects/$PROJECT_ID/jobs" \
  -H 'content-type: application/json' \
  -d "{\"job_type\":\"alignment\",\"book_asset_id\":\"$EPUB_ASSET_ID\",\"audio_asset_ids\":[\"$AUDIO_ASSET_ID\"]}")"
JOB_ID="$(printf '%s' "$JOB_JSON" | extract_json_field job_id)"

JOB_STATUS="queued"
MAX_POLLS=$((WAIT_SECONDS / POLL_SECONDS))
if (( MAX_POLLS < 1 )); then
  MAX_POLLS=1
fi

for ((poll = 1; poll <= MAX_POLLS; poll++)); do
  STATUS_JSON="$(curl -fsS "$API_BASE_URL/projects/$PROJECT_ID/jobs/$JOB_ID")"
  JOB_STATUS="$(printf '%s' "$STATUS_JSON" | extract_json_field status)"
  if [[ "$JOB_STATUS" == "completed" || "$JOB_STATUS" == "failed" || "$JOB_STATUS" == "cancelled" ]]; then
    printf '%s\n' "$STATUS_JSON" >"$OUTPUT_DIR/job-status.json"
    break
  fi
  sleep "$POLL_SECONDS"
done

curl -fsS "$API_BASE_URL/projects/$PROJECT_ID/jobs/$JOB_ID" >"$OUTPUT_DIR/job-status.json"

if [[ "$JOB_STATUS" != "completed" ]]; then
  echo "Alignment job did not complete successfully. Status: $JOB_STATUS" >&2
  if [[ -f "$ROOT_DIR/.run/backend-api.log" ]]; then
    echo "--- tail: $ROOT_DIR/.run/backend-api.log ---" >&2
    tail -n 40 "$ROOT_DIR/.run/backend-api.log" >&2 || true
  fi
  if [[ -f "$ROOT_DIR/.run/backend-worker.log" ]]; then
    echo "--- tail: $ROOT_DIR/.run/backend-worker.log ---" >&2
    tail -n 40 "$ROOT_DIR/.run/backend-worker.log" >&2 || true
  fi
  exit 1
fi

curl -fsS "$API_BASE_URL/projects/$PROJECT_ID/reader-model" >"$OUTPUT_DIR/reader-model.json"
curl -fsS "$API_BASE_URL/projects/$PROJECT_ID/sync" >"$OUTPUT_DIR/sync.json"

python3 - "$OUTPUT_DIR" "$PROJECT_ID" "$JOB_ID" "$JOB_STATUS" "$PROVIDER" <<'PY'
import json
import sys
from pathlib import Path

output_dir = Path(sys.argv[1])
project_id = sys.argv[2]
job_id = sys.argv[3]
job_status = sys.argv[4]
provider = sys.argv[5]

sync_payload = json.loads((output_dir / "sync.json").read_text())["inline_payload"]
job_payload = json.loads((output_dir / "job-status.json").read_text())

summary = {
    "project_id": project_id,
    "job_id": job_id,
    "job_status": job_status,
    "provider_hint": provider,
    "matched_tokens": len(sync_payload.get("tokens", [])),
    "gap_ranges": len(sync_payload.get("gaps", [])),
    "content_start_ms": sync_payload.get("content_start_ms"),
    "content_end_ms": sync_payload.get("content_end_ms"),
    "match_confidence": job_payload.get("quality", {}).get("match_confidence"),
}

(output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
PY

cat <<EOF
Smoke run complete.

Provider hint: $PROVIDER
Project ID: $PROJECT_ID
Job ID: $JOB_ID
Job status: $JOB_STATUS

Artifacts:
  $OUTPUT_DIR/reader-model.json
  $OUTPUT_DIR/sync.json
  $OUTPUT_DIR/job-status.json
  $OUTPUT_DIR/summary.json

Flutter:
  make flutter-run PROJECT_ID=$PROJECT_ID API_BASE_URL=$API_BASE_URL
EOF
