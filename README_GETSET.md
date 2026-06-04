# Odoo Get/Set Lead Recipe — Quick Start

This document explains how to test the `odoo_getset_lead` recipe locally.

Prereqs
- Docker + docker-compose (to run Postgres and Odoo locally)
- Python 3.10+ available for the test runner

Files added
- `recipes/odoo_getset_lead.py` — recipe implementation (callable `run(vars)`)
- `samples/odoo_getset_lead_insert.sql` — idempotent SQL to seed `cookbook_*` rows
- `tests/run_odoo_getset_lead.py` — simple local test runner

Run the DB & Odoo (example; adapt to your compose filenames):

```bash
# Start Odoo (if using the provided docker-compose)
docker compose -f "docker-compose (1).yml" up -d

# Start Postgres (pgvector image) if separate
docker compose -f docker-compose.yml up -d
```

Apply migrations and sample insert (adjust container name / paths):

```bash
# Example: apply migrations if you have the migration files in migrations/
docker exec -i hyve-postgres psql -1 -U hyve_admin -d hyve_llm < migrations/001_kitchen_schema.sql
docker exec -i hyve-postgres psql -1 -U hyve_admin -d hyve_llm < migrations/002_kitchen_async_jobs.sql
docker exec -i hyve-postgres psql -1 -U hyve_admin -d hyve_llm < migrations/003_cookbook_evolution.sql
docker exec -i hyve-postgres psql -1 -U hyve_admin -d hyve_llm < migrations/004_kitchen_extras.sql

# Apply the sample recipe insert (path in container must match where you copy it)
docker cp samples/odoo_getset_lead_insert.sql hyve-postgres:/tmp/
docker exec -i hyve-postgres psql -1 -U hyve_admin -d hyve_llm -f /tmp/odoo_getset_lead_insert.sql
```

Local test runner

Edit `tests/run_odoo_getset_lead.py` to add your local `odoo_password` (keep it secret).
Then run:

```bash
python -m tests.run_odoo_getset_lead
```

The test runner calls `run(vars)` and prints the returned envelope.

Security
- Do not check in passwords or API keys. Use local env vars or an external secrets manager.

If you'd like, I can adapt the SQL insert to put the full rendered `python_body` into `cookbook_recipe.python_body` instead of relying on a template row.
