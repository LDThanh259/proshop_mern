#!/usr/bin/env bash
set -euo pipefail

MON_DIR="${1:-$(cd "$(dirname "$0")/../monitoring-stack" && pwd)}"
TEMPLATE="${MON_DIR}/alertmanager/alertmanager.yml.template"
OUTPUT="${MON_DIR}/alertmanager/alertmanager.yml"

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "WARN: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set; alertmanager may fail to start" >&2
fi

export TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-replace_me}"
export TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-replace_me}"

envsubst '${TELEGRAM_BOT_TOKEN} ${TELEGRAM_CHAT_ID}' < "$TEMPLATE" > "$OUTPUT"
echo "Rendered alertmanager config -> $OUTPUT"
