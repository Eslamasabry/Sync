#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_BASE_URL="http://127.0.0.1:8000/v1"
WORK_DIR="$ROOT_DIR/tmp/public-domain-regression"
TITLE="The Yellow Wallpaper"
LANGUAGE="en"
EPUB_URL="https://www.gutenberg.org/ebooks/1952.epub3.images"
AUDIO_URL="https://commons.wikimedia.org/wiki/Special:FilePath/Yellow%20wallpaper%20gilman_lr.ogg"
EPUB_PATH="$WORK_DIR/the-yellow-wallpaper.epub"
AUDIO_PATH="$WORK_DIR/the-yellow-wallpaper.ogg"
EXCERPT_PATH="$WORK_DIR/the-yellow-wallpaper-5m.ogg"
EXCERPT_SECONDS=300
WAIT_SECONDS=450
POLL_SECONDS=5
MIN_MATCH_CONFIDENCE=""
MIN_COVERAGE=""
MAX_GAP_RANGES=""

usage() {
  cat <<'EOF'
Usage: scripts/local/run_public_domain_regression.sh [options]

Downloads a public-domain EPUB + audiobook pair, uploads them to the local API,
runs an alignment job, and prints quality metrics from the resulting sync artifact.

Options:
  --api-base-url URL         Backend API base URL. Default: http://127.0.0.1:8000/v1
  --work-dir PATH            Working directory for downloaded/generated files.
  --excerpt-seconds N        Audio excerpt length in seconds. Default: 300
  --wait-seconds N           Maximum seconds to wait for completion. Default: 450
  --poll-seconds N           Poll interval in seconds. Default: 5
  --min-match-confidence N   Fail if result is below this value.
  --min-coverage N           Fail if matched_tokens / transcript_words is below this value.
  --max-gap-ranges N         Fail if gap count exceeds this value.
EOF
}

extract_json_field() {
  local field="$1"
  python3 - "$field" <<'PY'
import json
import sys

field = sys.argv[1]
payload = json.load(sys.stdin)
print(payload[field])
PY
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
    --work-dir)
      WORK_DIR="${2:-}"
      EPUB_PATH="$WORK_DIR/the-yellow-wallpaper.epub"
      AUDIO_PATH="$WORK_DIR/the-yellow-wallpaper.ogg"
      EXCERPT_PATH="$WORK_DIR/the-yellow-wallpaper-5m.ogg"
      shift 2
      ;;
    --excerpt-seconds)
      EXCERPT_SECONDS="${2:-}"
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
    --min-match-confidence)
      MIN_MATCH_CONFIDENCE="${2:-}"
      shift 2
      ;;
    --min-coverage)
      MIN_COVERAGE="${2:-}"
      shift 2
      ;;
    --max-gap-ranges)
      MAX_GAP_RANGES="${2:-}"
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
require_cmd ffmpeg
require_cmd python3

mkdir -p "$WORK_DIR"

if ! curl -fsS "$API_BASE_URL/ready" >/dev/null; then
  echo "Backend is not ready at $API_BASE_URL/ready" >&2
  exit 1
fi

curl -fsSL "$EPUB_URL" -o "$EPUB_PATH"
curl -fsSL "$AUDIO_URL" -o "$AUDIO_PATH"
ffmpeg -y -i "$AUDIO_PATH" -t "$EXCERPT_SECONDS" -c copy "$EXCERPT_PATH" >/dev/null 2>&1

PROJECT_JSON="$(curl -fsS -X POST "$API_BASE_URL/projects" \
  -H 'content-type: application/json' \
  -d "{\"title\":\"$TITLE\",\"language\":\"$LANGUAGE\"}")"
PROJECT_ID="$(printf '%s' "$PROJECT_JSON" | extract_json_field project_id)"

EPUB_JSON="$(curl -fsS -X POST "$API_BASE_URL/projects/$PROJECT_ID/assets/upload" \
  -F kind=epub \
  -F "file=@$EPUB_PATH")"
EPUB_ASSET_ID="$(printf '%s' "$EPUB_JSON" | extract_json_field asset_id)"

AUDIO_JSON="$(curl -fsS -X POST "$API_BASE_URL/projects/$PROJECT_ID/assets/upload" \
  -F kind=audio \
  -F "file=@$EXCERPT_PATH")"
AUDIO_ASSET_ID="$(printf '%s' "$AUDIO_JSON" | extract_json_field asset_id)"

JOB_JSON="$(curl -fsS -X POST "$API_BASE_URL/projects/$PROJECT_ID/jobs" \
  -H 'content-type: application/json' \
  -d "{\"job_type\":\"alignment\",\"book_asset_id\":\"$EPUB_ASSET_ID\",\"audio_asset_ids\":[\"$AUDIO_ASSET_ID\"]}")"
JOB_ID="$(printf '%s' "$JOB_JSON" | extract_json_field job_id)"

MAX_POLLS=$((WAIT_SECONDS / POLL_SECONDS))
if (( MAX_POLLS < 1 )); then
  MAX_POLLS=1
fi

for ((poll = 1; poll <= MAX_POLLS; poll++)); do
  STATUS_JSON="$(curl -fsS "$API_BASE_URL/projects/$PROJECT_ID/jobs/$JOB_ID")"
  STATUS="$(printf '%s' "$STATUS_JSON" | extract_json_field status)"
  if [[ "$STATUS" == "completed" || "$STATUS" == "failed" || "$STATUS" == "cancelled" ]]; then
    printf '%s\n' "$STATUS_JSON" > "$WORK_DIR/job-status.json"
    break
  fi
  sleep "$POLL_SECONDS"
done

curl -fsS "$API_BASE_URL/projects/$PROJECT_ID/jobs/$JOB_ID" > "$WORK_DIR/job-status.json"
STATUS="$(python3 - "$WORK_DIR/job-status.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
print(payload["status"])
PY
)"

if [[ "$STATUS" != "completed" ]]; then
  echo "Regression job did not complete successfully. Status: $STATUS" >&2
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

curl -fsS "$API_BASE_URL/projects/$PROJECT_ID/sync" > "$WORK_DIR/sync.json"
curl -fsS "$API_BASE_URL/projects/$PROJECT_ID/jobs/$JOB_ID/transcript" > "$WORK_DIR/transcript.json"

python3 - "$WORK_DIR" "$PROJECT_ID" "$JOB_ID" \
  "$MIN_MATCH_CONFIDENCE" "$MIN_COVERAGE" "$MAX_GAP_RANGES" <<'PY'
import json
import sys
from pathlib import Path

work_dir = Path(sys.argv[1])
project_id = sys.argv[2]
job_id = sys.argv[3]
min_match_confidence = float(sys.argv[4]) if sys.argv[4] else None
min_coverage = float(sys.argv[5]) if sys.argv[5] else None
max_gap_ranges = int(sys.argv[6]) if sys.argv[6] else None

sync_payload = json.loads((work_dir / "sync.json").read_text())
inline = sync_payload["inline_payload"]
job_payload = json.loads((work_dir / "job-status.json").read_text())
transcript_payload = json.loads((work_dir / "transcript.json").read_text())["payload"]

transcript_words = sum(len(segment["words"]) for segment in transcript_payload["segments"])
matched_tokens = len(inline["tokens"])
gaps = len(inline["gaps"])
coverage = 0 if transcript_words == 0 else round(matched_tokens / transcript_words, 4)
match_confidence = job_payload["quality"]["match_confidence"]

metrics = {
    "project_id": project_id,
    "job_id": job_id,
    "status": job_payload["status"],
    "match_confidence": match_confidence,
    "transcript_words": transcript_words,
    "matched_tokens": matched_tokens,
    "gap_ranges": gaps,
    "coverage": coverage,
    "content_start_ms": inline["content_start_ms"],
    "content_end_ms": inline["content_end_ms"],
    "first_gap_reason": inline["gaps"][0]["reason"] if inline["gaps"] else None,
}

(work_dir / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")

print(f"PROJECT_ID={project_id}")
print(f"JOB_ID={job_id}")
print(f"STATUS={job_payload['status']}")
print(f"MATCH_CONFIDENCE={match_confidence}")
print(f"TRANSCRIPT_WORDS={transcript_words}")
print(f"MATCHED_TOKENS={matched_tokens}")
print(f"GAP_RANGES={gaps}")
print(f"COVERAGE={coverage}")
print(f"CONTENT_START_MS={inline['content_start_ms']}")
print(f"CONTENT_END_MS={inline['content_end_ms']}")
if inline["gaps"]:
    print("FIRST_GAP_REASON=" + inline["gaps"][0]["reason"])

failures = []
if min_match_confidence is not None and match_confidence < min_match_confidence:
    failures.append(
        f"match_confidence {match_confidence} is below threshold {min_match_confidence}"
    )
if min_coverage is not None and coverage < min_coverage:
    failures.append(f"coverage {coverage} is below threshold {min_coverage}")
if max_gap_ranges is not None and gaps > max_gap_ranges:
    failures.append(f"gap_ranges {gaps} exceeds threshold {max_gap_ranges}")

if failures:
    print("REGRESSION_RESULT=failed")
    for failure in failures:
        print("REGRESSION_FAILURE=" + failure)
    raise SystemExit(1)

print("REGRESSION_RESULT=passed")
PY

cat <<EOF

Artifacts saved under:
  $WORK_DIR
  $WORK_DIR/metrics.json
EOF
