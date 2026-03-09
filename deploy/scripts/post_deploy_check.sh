#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="http://127.0.0.1:8000/v1"
AUTH_TOKEN=""

usage() {
  cat <<'EOF'
Usage: deploy/scripts/post_deploy_check.sh [options]

Runs basic liveness/readiness checks against a self-hosted Sync deployment.

Options:
  --api-base-url URL   API base URL. Default: http://127.0.0.1:8000/v1
  --auth-token TOKEN   Optional bearer token for protected deployments
EOF
}

while (($# > 0)); do
  case "$1" in
    --api-base-url)
      API_BASE_URL="${2:-}"
      shift 2
      ;;
    --auth-token)
      AUTH_TOKEN="${2:-}"
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

AUTH_ARGS=()
if [[ -n "$AUTH_TOKEN" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer $AUTH_TOKEN")
fi

curl -fsS "${API_BASE_URL}/health" >/dev/null
curl -fsS "${API_BASE_URL}/ready" >/dev/null
curl -fsS "${AUTH_ARGS[@]}" -X POST "${API_BASE_URL}/projects" \
  -H 'content-type: application/json' \
  -d '{"title":"Deploy Check","language":"en"}' >/dev/null

echo "Deployment checks passed for ${API_BASE_URL}"
