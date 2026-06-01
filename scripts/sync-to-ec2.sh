#!/usr/bin/env bash
set -euo pipefail

# Sync deploy configs to EC2 (tar + sudo). Excludes .env on server.
# Usage:
#   export EC2_HOST=testuser@3.107.1.188
#   export SSH_KEY=/path/to/test_key
#   export SUDO_PASSWORD=testuser
#   ./scripts/sync-to-ec2.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EC2_HOST="${EC2_HOST:?Set EC2_HOST, e.g. testuser@3.107.1.188}"
SSH_KEY="${SSH_KEY:-}"
PROSHOP_DIR="${PROSHOP_DIR:-/opt/proshop}"
SUDO_PASSWORD="${SUDO_PASSWORD:-testuser}"

SSH_OPTS=(-o StrictHostKeyChecking=no)
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY")
fi

ARCHIVE="$(mktemp /tmp/proshop-deploy.XXXXXX.tgz)"
trap 'rm -f "$ARCHIVE"' EXIT

tar -czf "$ARCHIVE" -C "$ROOT" --exclude='.env' app-stack monitoring-stack scripts

scp "${SSH_OPTS[@]}" "$ARCHIVE" "$EC2_HOST:/tmp/proshop-deploy.tgz"

ssh "${SSH_OPTS[@]}" "$EC2_HOST" \
  "echo '$SUDO_PASSWORD' | sudo -S tar -xzf /tmp/proshop-deploy.tgz -C '$PROSHOP_DIR' && \
   echo '$SUDO_PASSWORD' | sudo -S chmod +x '$PROSHOP_DIR'/scripts/*.sh && \
   echo '$SUDO_PASSWORD' | sudo -S sed -i 's/\r$//' '$PROSHOP_DIR'/scripts/*.sh 2>/dev/null || true; \
   rm -f /tmp/proshop-deploy.tgz"

echo "Sync done. On server run deploy-ec2.sh (see docs/DEPLOY.md)."
