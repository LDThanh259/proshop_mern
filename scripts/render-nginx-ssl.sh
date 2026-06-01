#!/usr/bin/env bash
set -euo pipefail

APP_STACK_DIR="${1:-$(cd "$(dirname "$0")/../app-stack" && pwd)}"
TEMPLATE="${APP_STACK_DIR}/nginx/default.ssl.conf.template"
OUTPUT="${APP_STACK_DIR}/nginx/default.conf"

if [[ -z "${DOMAIN:-}" ]]; then
  echo "ERROR: DOMAIN is not set (example: export DOMAIN=proshop-mern.duckdns.org)" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: missing template: $TEMPLATE" >&2
  exit 1
fi

export DOMAIN
envsubst '${DOMAIN}' < "$TEMPLATE" > "$OUTPUT"
echo "Rendered SSL nginx config -> $OUTPUT (DOMAIN=$DOMAIN)"
