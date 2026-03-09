#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deploy/scripts/generate_api_auth_token.sh [--bytes N]

Generates a URL-safe bearer token for API_AUTH_TOKEN.

Options:
  --bytes N   Random byte length before URL-safe encoding. Default: 32
EOF
}

BYTE_LENGTH=32

while (($# > 0)); do
  case "$1" in
    --bytes)
      BYTE_LENGTH="${2:-}"
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

python3 - "$BYTE_LENGTH" <<'PY'
import base64
import secrets
import sys

size = int(sys.argv[1])
token = base64.urlsafe_b64encode(secrets.token_bytes(size)).decode("ascii").rstrip("=")
print(token)
PY
