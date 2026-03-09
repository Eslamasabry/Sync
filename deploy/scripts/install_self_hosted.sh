#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_ROOT="/opt/sync"
ENV_TARGET="/etc/sync/backend.env"
INSTALL_NGINX=1
ENABLE_WORKER=1

usage() {
  cat <<'EOF'
Usage: deploy/scripts/install_self_hosted.sh [options]

Copies the committed self-hosted templates into system locations and reloads
systemd/nginx. Run this as root on the target host.

Options:
  --install-root PATH   Repo checkout path on the host. Default: /opt/sync
  --env-target PATH     Backend env target path. Default: /etc/sync/backend.env
  --skip-nginx          Do not install or reload nginx config
  --inline              Install API service only, not the worker service
EOF
}

while (($# > 0)); do
  case "$1" in
    --install-root)
      INSTALL_ROOT="${2:-}"
      shift 2
      ;;
    --env-target)
      ENV_TARGET="${2:-}"
      shift 2
      ;;
    --skip-nginx)
      INSTALL_NGINX=0
      shift
      ;;
    --inline)
      ENABLE_WORKER=0
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

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

mkdir -p "$(dirname "$ENV_TARGET")"
cp "$ROOT_DIR/deploy/env/backend.env.example" "$ENV_TARGET"
chmod 640 "$ENV_TARGET"

install -m 0644 "$ROOT_DIR/deploy/systemd/sync-api.service" /etc/systemd/system/sync-api.service
if (( ENABLE_WORKER == 1 )); then
  install -m 0644 "$ROOT_DIR/deploy/systemd/sync-worker.service" /etc/systemd/system/sync-worker.service
fi
systemctl daemon-reload
systemctl enable sync-api
if (( ENABLE_WORKER == 1 )); then
  systemctl enable sync-worker
fi

if (( INSTALL_NGINX == 1 )); then
  install -m 0644 "$ROOT_DIR/deploy/nginx/sync.conf" /etc/nginx/sites-available/sync.conf
  ln -sf /etc/nginx/sites-available/sync.conf /etc/nginx/sites-enabled/sync.conf
  nginx -t
  systemctl reload nginx
fi

cat <<EOF
Installed templates:
  env: $ENV_TARGET
  api service: /etc/systemd/system/sync-api.service
EOF

if (( ENABLE_WORKER == 1 )); then
  echo "  worker service: /etc/systemd/system/sync-worker.service"
else
  echo "  worker service: skipped (--inline)"
fi

if (( INSTALL_NGINX == 1 )); then
  echo "  nginx config: /etc/nginx/sites-available/sync.conf"
else
  echo "  nginx config: skipped (--skip-nginx)"
fi

RESTART_SERVICES="sync-api"
if (( ENABLE_WORKER == 1 )); then
  RESTART_SERVICES="$RESTART_SERVICES sync-worker"
fi

cat <<EOF

Next:
  1. cd $INSTALL_ROOT
  2. Edit $ENV_TARGET
  3. systemctl restart $RESTART_SERVICES
  4. Run ./deploy/scripts/post_deploy_check.sh --api-base-url http://127.0.0.1:8000/v1
EOF
