#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROSHOP_DIR="${PROSHOP_DIR:-/opt/proshop}"
ENV_FILE="${ENV_FILE:-$PROSHOP_DIR/.env}"

echo "==> ProShop deploy (PROSHOP_DIR=$PROSHOP_DIR)"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  echo "Loaded env from $ENV_FILE"
fi

echo "==> Ensure Docker network: observability"
docker network inspect observability >/dev/null 2>&1 || docker network create observability

APP_DIR="$PROSHOP_DIR/app-stack"
MON_DIR="$PROSHOP_DIR/monitoring-stack"

if [[ -n "${DOMAIN:-}" ]] && [[ -f "$APP_DIR/nginx/default.ssl.conf.template" ]]; then
  echo "==> Render nginx SSL for DOMAIN=$DOMAIN"
  DOMAIN="$DOMAIN" bash "$ROOT/scripts/render-nginx-ssl.sh" "$APP_DIR"
elif [[ ! -f "$APP_DIR/nginx/default.conf" ]]; then
  echo "==> No DOMAIN set; using HTTP nginx config"
  cp "$APP_DIR/nginx/default.http.conf" "$APP_DIR/nginx/default.conf"
fi

if [[ -f "$ENV_FILE" ]]; then
  ln -sf "$ENV_FILE" "$APP_DIR/.env" 2>/dev/null || cp -f "$ENV_FILE" "$APP_DIR/.env"
fi

echo "==> Start app stack"
cd "$APP_DIR"
docker compose up -d

if [[ "${RUN_SEED:-false}" == "true" ]]; then
  echo "==> Run database seed (profile seed)"
  docker compose --profile seed up seed
fi

echo "==> Start monitoring stack (prod overrides)"
cd "$MON_DIR"
MON_ENV="${MON_DIR}/.env"
COMPOSE_ENV=()
if [[ -f "$MON_ENV" ]]; then
  COMPOSE_ENV=(--env-file "$MON_ENV")
fi
docker compose -f docker-compose.yml -f docker-compose.prod.yml "${COMPOSE_ENV[@]}" up -d

echo "==> Container status"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo "==> Health checks (best effort)"
curl -fsS "http://127.0.0.1/api/products/top" >/dev/null 2>&1 && echo "App API: OK" || echo "App API: check manually (HTTP or HTTPS)"
curl -fsS "http://127.0.0.1:9090/-/ready" >/dev/null 2>&1 && echo "Prometheus: OK" || echo "Prometheus: not ready"
curl -fsS "http://127.0.0.1:3000/api/health" >/dev/null 2>&1 && echo "Grafana: OK" || echo "Grafana: not ready"

echo "Deploy finished."
