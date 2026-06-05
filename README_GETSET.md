# Local deploy

```bash
cp .env.example .env
./scripts/deploy_local.sh --init-pg   # kitchen PG + schema + Odoo
./scripts/deploy_local.sh --skip-pg   # Odoo only
```

## Databases

| Stack | What spins up | You use |
|-------|----------------|---------|
| Kitchen (`docker-compose-pg.yml`) | `KITCHEN_PG_DB` (default `test_db`) | Cookbook SQL, tier4 samples. Run `--init-pg` to apply `001`–`004` migrations. |
| Odoo (`docker-compose-odoo.yml` `db`) | Postgres role `ODOO_DB_USER`; server DB `postgres` | Internal only — Odoo manages this. |
| Odoo app | Not auto-created | Open Odoo UI, create DB named `ODOO_DB` (default `hyve_kitchen`). |

Kitchen and Odoo Postgres are separate. `ODOO_DB_*` is Odoo’s DB server creds. `KITCHEN_PG_*` is the pgvector dev DB on your host port.

If you change `ODOO_HOST_PORT`, set `ODOO_BASE_URL` to match.

## Odoo Get/Set Lead Recipe

This document explains how to test the `odoo_getset_lead` recipe locally.

Prereqs:
- Docker + docker compose
- Python 3.10+
- Local `.env` copied from `.env.example`

Files:
- `recipes/odoo_getset_lead.py` - recipe implementation, callable as `run(vars)`
- `samples/odoo_getset_lead_insert.sql` - idempotent SQL to seed `cookbook_*` rows
- `tests/run_odoo_getset_lead.py` - simple local test runner

Apply migrations and sample inserts after the kitchen Postgres container is up:

```bash
docker exec -i pg_test_db psql -v ON_ERROR_STOP=1 -U "$KITCHEN_PG_USER" -d "$KITCHEN_PG_DB" < samples/odoo_getset_lead_insert.sql
```

Run the test:

```bash
set -a && source .env && set +a
python -m tests.run_odoo_getset_lead
```

The test runner calls `run(vars)` and prints the returned envelope.

Security:
- Do not commit `.env`, passwords, or API keys.
