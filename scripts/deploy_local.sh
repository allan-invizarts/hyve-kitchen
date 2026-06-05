#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

COMPOSE_PG="$ROOT/docker-compose-pg.yml"
COMPOSE_ODOO="$ROOT/docker-compose-odoo.yml"
PG_PORT="${POSTGRES_HOST_PORT:-5432}"
ODOO_PORT="${ODOO_HOST_PORT:-8069}"
KITCHEN_PG_USER="${KITCHEN_PG_USER:-test_user}"
KITCHEN_PG_DB="${KITCHEN_PG_DB:-test_db}"
SKIP_PG=false
INIT_PG=false

usage() {
  echo "Usage: $0 [--skip-pg] [--init-pg]"
  exit "${1:-0}"
}

for arg in "$@"; do
  case "$arg" in
    --skip-pg|--no-pg) SKIP_PG=true ;;
    --init-pg) INIT_PG=true ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown: $arg" >&2; usage 1 ;;
  esac
done

command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }

wait_until() {
  local label=$1 tries=$2 interval=$3
  shift 3
  local n=0
  while [ "$n" -lt "$tries" ]; do
    if "$@"; then return 0; fi
    sleep "$interval"
    n=$((n + 1))
  done
  echo "Timed out: $label" >&2
  return 1
}

postgres_healthy() {
  [ "$(docker inspect --format='{{.State.Health.Status}}' pg_test_db 2>/dev/null || true)" = "healthy" ]
}

odoo_up() {
  curl -sf --connect-timeout 2 "http://127.0.0.1:${ODOO_PORT}/web/database/selector" -o /dev/null
}

up() {
  docker compose -f "$1" up -d
}

init_kitchen_pg() {
  for f in "$ROOT"/00{1,2,3,4}_*.sql; do
    [ -f "$f" ] || continue
    echo "Applying $(basename "$f")..."
    docker exec -i pg_test_db psql -v ON_ERROR_STOP=1 -U "$KITCHEN_PG_USER" -d "$KITCHEN_PG_DB" < "$f"
  done
}

mkdir -p "$ROOT/addons"

if [ "$SKIP_PG" = false ]; then
  up "$COMPOSE_PG"
  wait_until "postgres" 60 2 postgres_healthy || {
    echo "docker compose -f $COMPOSE_PG logs postgres-test" >&2
    exit 1
  }
  if [ "$INIT_PG" = true ]; then
    init_kitchen_pg
  fi
fi

up "$COMPOSE_ODOO"
wait_until "odoo" 90 2 odoo_up || {
  echo "docker compose -f $COMPOSE_ODOO logs web" >&2
  exit 1
}

if [ "$SKIP_PG" = false ]; then
  echo "Kitchen PG  localhost:${PG_PORT}  db=${KITCHEN_PG_DB}  user=${KITCHEN_PG_USER}"
fi
echo "Odoo        http://localhost:${ODOO_PORT}"
echo "Odoo app DB create at first login: ${ODOO_DB:-hyve_kitchen}"
echo "Test        set -a && source .env && set +a && python -m tests.run_odoo_getset_lead"
