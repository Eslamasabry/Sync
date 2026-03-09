#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_BASE_URL="http://127.0.0.1:8000/v1"
CORPUS_PATH="$ROOT_DIR/scripts/local/public_domain_regression_corpus.json"
WORK_DIR="$ROOT_DIR/tmp/regression-corpus"
FAIL_FAST=0
ENFORCE_THRESHOLDS=0
SELECTED_CASE_IDS=()

usage() {
  cat <<'EOF'
Usage: scripts/local/run_regression_corpus.sh [options]

Runs the real public-domain regression corpus defined in
scripts/local/public_domain_regression_corpus.json and aggregates per-title
results into a single summary artifact.

Options:
  --api-base-url URL   Backend API base URL. Default: http://127.0.0.1:8000/v1
  --corpus-path PATH   Regression corpus manifest path.
  --work-dir PATH      Output directory for per-case artifacts and summary files.
  --case-id ID         Run only the specified case id. Repeatable.
  --gate               Enforce per-case thresholds from the corpus manifest.
  --fail-fast          Stop after the first failing case.
EOF
}

while (($# > 0)); do
  case "$1" in
    --api-base-url)
      API_BASE_URL="${2:-}"
      shift 2
      ;;
    --corpus-path)
      CORPUS_PATH="${2:-}"
      shift 2
      ;;
    --work-dir)
      WORK_DIR="${2:-}"
      shift 2
      ;;
    --case-id)
      SELECTED_CASE_IDS+=("${2:-}")
      shift 2
      ;;
    --gate)
      ENFORCE_THRESHOLDS=1
      shift
      ;;
    --fail-fast)
      FAIL_FAST=1
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

mkdir -p "$WORK_DIR"
SELECTION_JSON="$(python3 - "${SELECTED_CASE_IDS[@]}" <<'PY'
import json
import sys

print(json.dumps(sys.argv[1:]))
PY
)"

mapfile -t CASE_LINES < <(python3 - "$CORPUS_PATH" "$SELECTION_JSON" <<'PY'
import json
import sys
from pathlib import Path

corpus = json.loads(Path(sys.argv[1]).read_text())
selected_ids = set(json.loads(sys.argv[2]))
cases = corpus["cases"]

if selected_ids:
    cases = [case for case in cases if case["id"] in selected_ids]
    missing = sorted(selected_ids.difference(case["id"] for case in cases))
    if missing:
        raise SystemExit("Unknown case ids: " + ", ".join(missing))

for case in cases:
    print(json.dumps(case))
PY
)

if [[ ${#CASE_LINES[@]} -eq 0 ]]; then
  echo "No regression cases selected" >&2
  exit 1
fi

FAILURES=0
for case_json in "${CASE_LINES[@]}"; do
  mapfile -t CASE_ARGS < <(python3 - "$case_json" "$API_BASE_URL" "$WORK_DIR" "$ENFORCE_THRESHOLDS" <<'PY'
import json
import sys

case = json.loads(sys.argv[1])
api_base_url = sys.argv[2]
work_dir = sys.argv[3]
enforce_thresholds = sys.argv[4] == "1"
thresholds = case.get("thresholds", {})

args = [
    "./scripts/local/run_public_domain_regression.sh",
    "--api-base-url", api_base_url,
    "--work-dir", f"{work_dir}/{case['id']}",
    "--case-id", case["id"],
    "--title", case["title"],
    "--language", case["language"],
    "--epub-url", case["epub_url"],
    "--excerpt-seconds", str(case.get("excerpt_seconds", 0)),
]

for audio_url in case["audio_urls"]:
    args.extend(["--audio-url", audio_url])

if enforce_thresholds:
    if "min_match_confidence" in thresholds:
        args.extend(["--min-match-confidence", str(thresholds["min_match_confidence"])])
    if "min_coverage" in thresholds:
        args.extend(["--min-coverage", str(thresholds["min_coverage"])])
    if "max_gap_ranges" in thresholds:
        args.extend(["--max-gap-ranges", str(thresholds["max_gap_ranges"])])

for item in args:
    print(item)
PY
  )

  case_id="$(python3 - "$case_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1])["id"])
PY
)"

  echo "==> Running regression case: $case_id"
  if "${CASE_ARGS[@]}"; then
    :
  else
    FAILURES=$((FAILURES + 1))
    if (( FAIL_FAST == 1 )); then
      break
    fi
  fi
done

python3 - "$CORPUS_PATH" "$WORK_DIR" "$SELECTION_JSON" "$ENFORCE_THRESHOLDS" <<'PY'
import json
import os
import sys
from pathlib import Path

corpus = json.loads(Path(sys.argv[1]).read_text())
work_dir = Path(sys.argv[2])
selected_ids = set(json.loads(sys.argv[3]))
gate_enabled = sys.argv[4] == "1"
cases_summary = []
missing_case_ids = []
selected_cases = []

for case in corpus["cases"]:
    if selected_ids and case["id"] not in selected_ids:
        continue
    selected_cases.append(case)
    metrics_path = work_dir / case["id"] / "metrics.json"
    if not metrics_path.exists():
        missing_case_ids.append(case["id"])
        continue
    metrics = json.loads(metrics_path.read_text())
    metrics["thresholds"] = case.get("thresholds", {})
    cases_summary.append(metrics)

failed_case_ids = [
    case["case_id"]
    for case in cases_summary
    if case.get("regression_result") != "passed"
]
overall_result = "passed"
if missing_case_ids or failed_case_ids:
    overall_result = "failed"

summary = {
    "corpus_id": corpus.get("corpus_id", Path(sys.argv[1]).stem),
    "gate_enabled": gate_enabled,
    "expected_case_count": len(selected_cases),
    "case_count": len(cases_summary),
    "missing_case_count": len(missing_case_ids),
    "missing_case_ids": missing_case_ids,
    "passed_count": sum(
        1 for case in cases_summary if case.get("regression_result") == "passed"
    ),
    "failed_case_count": len(failed_case_ids),
    "failed_case_ids": failed_case_ids,
    "overall_result": overall_result,
    "cases": cases_summary,
}

(work_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
summary_lines = [
    "# Regression Corpus Summary",
    "",
    f"- Corpus: `{summary['corpus_id']}`",
    f"- Gate enabled: `{str(gate_enabled).lower()}`",
    f"- Overall result: `{overall_result}`",
    f"- Cases completed: `{summary['case_count']}/{summary['expected_case_count']}`",
    f"- Passed: `{summary['passed_count']}`",
    f"- Failed: `{summary['failed_case_count']}`",
]
if missing_case_ids:
    summary_lines.append(f"- Missing cases: `{', '.join(missing_case_ids)}`")
summary_lines.extend(
    [
        "",
        "| Case | Result | Confidence | Coverage | Gaps | Thresholds |",
        "| --- | --- | ---: | ---: | ---: | --- |",
    ]
)
for case in cases_summary:
    thresholds = case.get("thresholds", {})
    threshold_label = ", ".join(
        f"{key}={value}" for key, value in thresholds.items()
    ) or "none"
    summary_lines.append(
        "| {case_id} | {result} | {confidence:.4f} | {coverage:.4f} | {gaps} | {thresholds} |".format(
            case_id=case["case_id"],
            result=case.get("regression_result", "unknown"),
            confidence=float(case.get("match_confidence") or 0.0),
            coverage=float(case.get("coverage") or 0.0),
            gaps=int(case.get("gap_ranges") or 0),
            thresholds=threshold_label,
        )
    )

summary_markdown = "\n".join(summary_lines) + "\n"
(work_dir / "summary.md").write_text(summary_markdown)
if "GITHUB_STEP_SUMMARY" in os.environ:
    Path(os.environ["GITHUB_STEP_SUMMARY"]).write_text(
        summary_markdown,
        encoding="utf-8",
    )
print(json.dumps(summary, indent=2))
PY

if (( FAILURES > 0 )); then
  echo "Regression corpus failed in $FAILURES case(s)." >&2
  exit 1
fi

if python3 - "$WORK_DIR/summary.json" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text())
raise SystemExit(0 if summary["overall_result"] == "passed" else 1)
PY
then
  :
else
  echo "Regression corpus summary reported a failed overall result." >&2
  exit 1
fi

echo "Regression corpus passed. Summary saved to $WORK_DIR/summary.json"
