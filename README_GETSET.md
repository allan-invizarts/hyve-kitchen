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
