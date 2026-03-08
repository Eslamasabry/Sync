#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_BASE_URL="http://127.0.0.1:8000/v1"
WORK_DIR="$ROOT_DIR/tmp/public-domain-regression"
CASE_ID="yellow-wallpaper"
TITLE="The Yellow Wallpaper"
LANGUAGE="en"
EPUB_URL="https://www.gutenberg.org/ebooks/1952.epub3.images"
AUDIO_URLS=("https://commons.wikimedia.org/wiki/Special:FilePath/Yellow%20wallpaper%20gilman_lr.ogg")
EXCERPT_SECONDS=300
WAIT_SECONDS=450
POLL_SECONDS=5
MIN_MATCH_CONFIDENCE=""
MIN_COVERAGE=""
MAX_GAP_RANGES=""

usage() {
  cat <<'EOF'
Usage: scripts/local/run_public_domain_regression.sh [options]

Downloads a real public-domain EPUB + audiobook pair, uploads them to the local
API, runs an alignment job, and prints quality metrics from the resulting sync
artifact.

Options:
  --api-base-url URL         Backend API base URL. Default: http://127.0.0.1:8000/v1
  --work-dir PATH            Working directory for downloaded/generated files.
  --case-id ID               Stable case identifier. Default: yellow-wallpaper
  --title TEXT               Project title for the regression run.
  --language CODE            Language hint passed to the project. Default: en
  --epub-url URL             EPUB download URL.
  --audio-url URL            Audio download URL. Repeat for multipart audiobooks.
  --excerpt-seconds N        Trim each audio file to N seconds. Use 0 to skip trimming.
                             Default: 300
  --wait-seconds N           Maximum seconds to wait for completion. Default: 450
  --poll-seconds N           Poll interval in seconds. Default: 5
  --min-match-confidence N   Fail if result is below this value.
  --min-coverage N           Fail if matched_tokens / transcript_words is below this value.
  --max-gap-ranges N         Fail if gap count exceeds this value.
EOF
}

extract_json_field() {
  local field="$1"
  python3 -c '
import json
import sys

payload = json.load(sys.stdin)
print(payload[sys.argv[1]])
' "$field"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

infer_extension() {
  local url="$1"
  local fallback="$2"
  python3 - "$url" "$fallback" <<'PY'
import os
import sys
from urllib.parse import urlparse, unquote

url = sys.argv[1]
fallback = sys.argv[2]
path = unquote(urlparse(url).path)
_, ext = os.path.splitext(path)
ext = ext.lstrip(".").lower()
print(ext or fallback)
PY
}

json_array() {
  python3 - "$@" <<'PY'
import json
import sys

print(json.dumps(sys.argv[1:]))
PY
}

download_audio_assets() {
  local download_dir="$1"
  local excerpt_dir="$2"
  local -n urls_ref="$3"
  local -n outputs_ref="$4"

  local index=0
  for url in "${urls_ref[@]}"; do
    index=$((index + 1))
    local ext
    ext="$(infer_extension "$url" "bin")"
    local source_path="$download_dir/${CASE_ID}-audio-$(printf '%02d' "$index").$ext"
    curl -fsSL "$url" -o "$source_path"

    if (( EXCERPT_SECONDS > 0 )); then
      local excerpt_path="$excerpt_dir/${CASE_ID}-audio-$(printf '%02d' "$index").$ext"
      ffmpeg -y -i "$source_path" -t "$EXCERPT_SECONDS" -c copy "$excerpt_path" >/dev/null 2>&1
      outputs_ref+=("$excerpt_path")
    else
      outputs_ref+=("$source_path")
    fi
  done
}

while (($# > 0)); do
  case "$1" in
    --api-base-url)
      API_BASE_URL="${2:-}"
      shift 2
      ;;
    --work-dir)
      WORK_DIR="${2:-}"
      shift 2
      ;;
    --case-id)
      CASE_ID="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --language)
      LANGUAGE="${2:-}"
      shift 2
      ;;
    --epub-url)
      EPUB_URL="${2:-}"
      shift 2
      ;;
    --audio-url)
      if [[ ${#AUDIO_URLS[@]} -eq 1 && "${AUDIO_URLS[0]}" == "https://commons.wikimedia.org/wiki/Special:FilePath/Yellow%20wallpaper%20gilman_lr.ogg" ]]; then
        AUDIO_URLS=()
      fi
      AUDIO_URLS+=("${2:-}")
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

if [[ -z "$CASE_ID" || -z "$TITLE" || -z "$LANGUAGE" || -z "$EPUB_URL" ]]; then
  echo "case-id, title, language, and epub-url are required" >&2
  exit 1
fi
if [[ ${#AUDIO_URLS[@]} -eq 0 ]]; then
  echo "At least one --audio-url is required" >&2
  exit 1
fi

require_cmd curl
require_cmd python3
if (( EXCERPT_SECONDS > 0 )); then
  require_cmd ffmpeg
fi

mkdir -p "$WORK_DIR"
DOWNLOAD_DIR="$WORK_DIR/downloads"
EXCERPT_DIR="$WORK_DIR/excerpts"
mkdir -p "$DOWNLOAD_DIR" "$EXCERPT_DIR"

if ! curl -fsS "$API_BASE_URL/ready" >/dev/null; then
  echo "Backend is not ready at $API_BASE_URL/ready" >&2
  exit 1
fi

EPUB_EXT="$(infer_extension "$EPUB_URL" "epub")"
EPUB_PATH="$DOWNLOAD_DIR/${CASE_ID}.${EPUB_EXT}"
curl -fsSL "$EPUB_URL" -o "$EPUB_PATH"

UPLOAD_AUDIO_PATHS=()
download_audio_assets "$DOWNLOAD_DIR" "$EXCERPT_DIR" AUDIO_URLS UPLOAD_AUDIO_PATHS

printf '%s\n' "$TITLE" > "$WORK_DIR/title.txt"
printf '%s\n' "$EPUB_URL" > "$WORK_DIR/epub-url.txt"
printf '%s\n' "${AUDIO_URLS[@]}" > "$WORK_DIR/audio-urls.txt"

PROJECT_JSON="$(curl -fsS -X POST "$API_BASE_URL/projects" \
  -H 'content-type: application/json' \
  -d "{\"title\":\"$TITLE\",\"language\":\"$LANGUAGE\"}")"
PROJECT_ID="$(printf '%s' "$PROJECT_JSON" | extract_json_field project_id)"

EPUB_JSON="$(curl -fsS -X POST "$API_BASE_URL/projects/$PROJECT_ID/assets/upload" \
  -F kind=epub \
  -F "file=@$EPUB_PATH")"
EPUB_ASSET_ID="$(printf '%s' "$EPUB_JSON" | extract_json_field asset_id)"

AUDIO_ASSET_IDS=()
for audio_path in "${UPLOAD_AUDIO_PATHS[@]}"; do
  AUDIO_JSON="$(curl -fsS -X POST "$API_BASE_URL/projects/$PROJECT_ID/assets/upload" \
    -F kind=audio \
    -F "file=@$audio_path")"
  AUDIO_ASSET_IDS+=("$(printf '%s' "$AUDIO_JSON" | extract_json_field asset_id)")
done

AUDIO_ASSET_IDS_JSON="$(json_array "${AUDIO_ASSET_IDS[@]}")"
JOB_JSON="$(python3 - "$EPUB_ASSET_ID" "$AUDIO_ASSET_IDS_JSON" <<'PY'
import json
import sys

book_asset_id = sys.argv[1]
audio_asset_ids = json.loads(sys.argv[2])
print(json.dumps({
    "job_type": "alignment",
    "book_asset_id": book_asset_id,
    "audio_asset_ids": audio_asset_ids,
}))
PY
)"

JOB_RESPONSE_JSON="$(curl -fsS -X POST "$API_BASE_URL/projects/$PROJECT_ID/jobs" \
  -H 'content-type: application/json' \
  -d "$JOB_JSON")"
JOB_ID="$(printf '%s' "$JOB_RESPONSE_JSON" | extract_json_field job_id)"

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

python3 - "$WORK_DIR" "$CASE_ID" "$TITLE" "$LANGUAGE" "$PROJECT_ID" "$JOB_ID" \
  "$MIN_MATCH_CONFIDENCE" "$MIN_COVERAGE" "$MAX_GAP_RANGES" <<'PY'
import json
import sys
from pathlib import Path

work_dir = Path(sys.argv[1])
case_id = sys.argv[2]
title = sys.argv[3]
language = sys.argv[4]
project_id = sys.argv[5]
job_id = sys.argv[6]
min_match_confidence = float(sys.argv[7]) if sys.argv[7] else None
min_coverage = float(sys.argv[8]) if sys.argv[8] else None
max_gap_ranges = int(sys.argv[9]) if sys.argv[9] else None

sync_payload = json.loads((work_dir / "sync.json").read_text())
inline = sync_payload.get("inline_payload", sync_payload)
job_payload = json.loads((work_dir / "job-status.json").read_text())
transcript_payload = json.loads((work_dir / "transcript.json").read_text())["payload"]

transcript_words = sum(len(segment["words"]) for segment in transcript_payload["segments"])
matched_tokens = len(inline["tokens"])
gaps = len(inline["gaps"])
coverage = 0 if transcript_words == 0 else round(matched_tokens / transcript_words, 4)
stats = inline.get("stats", {})
match_confidence = job_payload["quality"]["match_confidence"]

metrics = {
    "case_id": case_id,
    "title": title,
    "language": language,
    "project_id": project_id,
    "job_id": job_id,
    "status": job_payload["status"],
    "match_confidence": match_confidence,
    "transcript_words": transcript_words,
    "matched_tokens": matched_tokens,
    "gap_ranges": gaps,
    "coverage": coverage,
    "audio_asset_count": len(inline.get("audio", [])),
    "content_start_ms": inline["content_start_ms"],
    "content_end_ms": inline["content_end_ms"],
    "first_gap_reason": inline["gaps"][0]["reason"] if inline["gaps"] else None,
    "stats": stats,
}

print(f"CASE_ID={case_id}")
print(f"TITLE={title}")
print(f"PROJECT_ID={project_id}")
print(f"JOB_ID={job_id}")
print(f"STATUS={job_payload['status']}")
print(f"MATCH_CONFIDENCE={match_confidence}")
print(f"TRANSCRIPT_WORDS={transcript_words}")
print(f"MATCHED_TOKENS={matched_tokens}")
print(f"GAP_RANGES={gaps}")
print(f"COVERAGE={coverage}")
print(f"AUDIO_ASSET_COUNT={len(inline.get('audio', []))}")
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
    metrics["regression_result"] = "failed"
    metrics["regression_failures"] = failures
    (work_dir / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    print("REGRESSION_RESULT=failed")
    for failure in failures:
        print("REGRESSION_FAILURE=" + failure)
    raise SystemExit(1)

metrics["regression_result"] = "passed"
metrics["regression_failures"] = []
(work_dir / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
print("REGRESSION_RESULT=passed")
PY

cat <<EOF

Artifacts saved under:
  $WORK_DIR
  $WORK_DIR/metrics.json
EOF
