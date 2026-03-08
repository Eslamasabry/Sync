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

usage() {
  cat <<'EOF'
Usage: scripts/local/run_public_domain_regression.sh [options]

Downloads a public-domain EPUB + audiobook pair, uploads them to the local API,
runs an alignment job, and prints quality metrics from the resulting sync artifact.

Options:
  --api-base-url URL         Backend API base URL. Default: http://127.0.0.1:8000/v1
  --work-dir PATH            Working directory for downloaded/generated files.
  --excerpt-seconds N        Audio excerpt length in seconds. Default: 300
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

mkdir -p "$WORK_DIR"

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

for _ in {1..90}; do
  STATUS_JSON="$(curl -fsS "$API_BASE_URL/projects/$PROJECT_ID/jobs/$JOB_ID")"
  STATUS="$(printf '%s' "$STATUS_JSON" | extract_json_field status)"
  if [[ "$STATUS" == "completed" || "$STATUS" == "failed" || "$STATUS" == "cancelled" ]]; then
    printf '%s\n' "$STATUS_JSON" > "$WORK_DIR/job-status.json"
    break
  fi
  sleep 5
done

curl -fsS "$API_BASE_URL/projects/$PROJECT_ID/sync" > "$WORK_DIR/sync.json"
curl -fsS "$API_BASE_URL/projects/$PROJECT_ID/jobs/$JOB_ID/transcript" > "$WORK_DIR/transcript.json"

python3 - "$WORK_DIR" "$PROJECT_ID" "$JOB_ID" <<'PY'
import json
import sys
from pathlib import Path

work_dir = Path(sys.argv[1])
project_id = sys.argv[2]
job_id = sys.argv[3]

sync_payload = json.loads((work_dir / "sync.json").read_text())
inline = sync_payload["inline_payload"]
job_payload = json.loads((work_dir / "job-status.json").read_text())
transcript_payload = json.loads((work_dir / "transcript.json").read_text())["payload"]

transcript_words = sum(len(segment["words"]) for segment in transcript_payload["segments"])
matched_tokens = len(inline["tokens"])
gaps = len(inline["gaps"])
coverage = 0 if transcript_words == 0 else round(matched_tokens / transcript_words, 4)

print(f"PROJECT_ID={project_id}")
print(f"JOB_ID={job_id}")
print(f"STATUS={job_payload['status']}")
print(f"MATCH_CONFIDENCE={job_payload['quality']['match_confidence']}")
print(f"TRANSCRIPT_WORDS={transcript_words}")
print(f"MATCHED_TOKENS={matched_tokens}")
print(f"GAP_RANGES={gaps}")
print(f"COVERAGE={coverage}")
print(f"CONTENT_START_MS={inline['content_start_ms']}")
print(f"CONTENT_END_MS={inline['content_end_ms']}")
if inline["gaps"]:
    print("FIRST_GAP_REASON=" + inline["gaps"][0]["reason"])
PY

cat <<EOF

Artifacts saved under:
  $WORK_DIR
EOF
