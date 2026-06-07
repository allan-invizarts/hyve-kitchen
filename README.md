# Hyve Kitchen: Phase 2 Analytics Recipe Architecture

A modular, tier-based analytics platform for Odoo CRM integration. This repo demonstrates the **Hyve Phase 2** recipe architecture: a clean separation between raw data access (Tier 3), semantic normalization (Tier 3.5), and analytics (Tier 4).

## Quick Overview

**What is this?**
- A local Odoo CRM instance (via Docker Compose) with Python-based recipe helpers.
- Three recipe layers that work together to transform raw CRM data into actionable customer insights.
- Blueprint for how analytics recipes should be authored and chained in the Hyve system.

**Why this structure?**
- **Tier 3 (CRUD)**: Raw access to Odoo data. No assumptions about output shape.
- **Tier 3.5 (Normalizer)**: Transform raw Odoo data into a canonical "Common Data Model" (CDM).
- **Tier 4 (Analyzer)**: Consume CDM and produce analytics (risk scores, engagement tiers, etc.).

Each tier is independently deployable, testable, and reusable.

---

## Architecture: Three Tiers in Action

### Tier 3: Raw Data Access (`odoo_crm_crud.py`)

**Purpose**: CRUD helper for Odoo `crm.lead` records.

**What it does**:
- Create, read, update, delete, search leads via Odoo JSON-RPC.
- Returns raw Odoo payloads (e.g., `{id: 123, name: "John", email_from: "john@..."}`)

**No normalization**: The raw output is exactly what Odoo gives you.

**Location**: `recipes/odoo/crm/odoo_crm_crud.py` + `recipes/odoo/crm/odoo_crm_crud.sql` (Phase 2 registration)

**Example output**:
```json
{
  "status": "SUCCESS",
  "data": {
    "lead_id": 42,
    "lead": {
      "id": 42,
      "name": "Allan Abendanio",
      "email_from": "allan@example.com",
      "phone": "+1-555-1234",
      "create_date": "2026-06-05 10:00:00"
    }
  }
}
```

---

### Tier 3.5: Semantic Normalization (`normalize_customer_profile.py`)

**Purpose**: Transform raw Odoo lead into a **Common Data Model** (CDM).

**What it does**:
- Consumes raw Odoo lead (from Tier 3).
- Maps Odoo fields to canonical `CommonCustomerProfile` structure.
- Returns normalized dict with guaranteed field names and types.

**Why it exists**: Tier 4 analyzers should never care about Odoo field names. They work with standardized CDM.

**Location**: `recipes/_normalizers/CommonCustomerProfile/normalize_customer_profile.py` + `.sql` (Phase 2 registration)

**Example output**:
```json
{
  "status": "SUCCESS",
  "data": {
    "normalized_profile": {
      "customer_id": 42,
      "name": "Allan Abendanio",
      "email": "allan@example.com",
      "phone": "+1-555-1234",
      "created_date": "2026-06-05T10:00:00Z",
      "last_activity": "2026-06-05T15:30:00Z",
      "loyalty_status": {
        "points_balance": 250,
        "tier": "gold"
      }
    }
  }
}
```

---

### Tier 4: Analytics (`analyze_customer_profile_summary.py`)

**Purpose**: Consume CDM and produce analytics.

**What it does**:
- Reads normalized `CommonCustomerProfile` from Tier 3.5.
- Computes engagement/risk metrics:
  - **Risk Score** (0-100): likelihood of churn based on email, phone, loyalty, activity recency.
  - **Engagement Tier** (premium/standard/basic/unknown): classification based on data completeness and loyalty.
  - **Risk Narrative**: human-readable summary.

**Why it's Tier 4**: Sits at the top; final analytics output. Consumes CDM, produces analytics CDM.

**Location**: `recipes/odoo/crm/analyze_customer_profile_summary.py` + `.sql` (Phase 2 registration)

**Example output**:
```json
{
  "status": "SUCCESS",
  "data": {
    "customer_id": 42,
    "risk_score": 35.5,
    "engagement_tier": "standard",
    "risk_narrative": "Low risk: customer showing positive engagement signals.",
    "summary": {
      "customer_id": 42,
      "name": "Allan Abendanio",
      "email": "allan@example.com",
      "phone": "+1-555-1234",
      "risk_score": 35.5,
      "engagement_tier": "standard",
      "created_date": "2026-06-05T10:00:00Z",
      "last_activity": "2026-06-05T15:30:00Z",
      "loyalty_status": {"points_balance": 250, "tier": "gold"}
    }
  }
}
```

---

## Directory Structure

```
hyve-kitchen/
├── README.md (this file)
├── docker-compose.yml          # Odoo + PostgreSQL stack
├── requirements.txt             # Python dependencies
│
├── recipes/
│   ├── odoo/
│   │   ├── crm/
│   │   │   ├── odoo_crm_crud.py              # Tier 3 CRUD helper
│   │   │   ├── odoo_crm_crud.sql             # Phase 2 recipe registration
│   │   │   ├── analyze_customer_profile_summary.py    # Tier 4 analyzer
│   │   │   ├── analyze_customer_profile_summary.sql   # Phase 2 recipe registration
│   │   │   ├── predict_customer_ltv.py       # Tier 5 LTV prediction
│   │   │   └── predict_customer_ltv.sql      # Phase 2 recipe registration
│   │   └── inventory/
│   │       ├── odoo_get_inventory.py         # Tier 3 inventory fetch
│   │       ├── odoo_get_inventory.sql
│   │       ├── odoo_inventory_crud.py        # Tier 3 inventory CRUD
│   │       ├── odoo_inventory_crud.sql
│   │       ├── analyze_inventory_gaps.py     # Tier 4 inventory analysis
│   │       ├── analyze_inventory_gaps.sql
│   │       ├── simulate_inventory_change.py  # Tier 5 inventory simulation
│   │       └── simulate_inventory_change.sql
│   
│   └── _normalizers/
│       ├── CommonCustomerProfile/
│       │   ├── normalize_customer_profile.py    # Tier 3.5 normalizer
│       │   └── normalize_customer_profile.sql   # Phase 2 recipe registration
│       └── Inventory/
│           ├── normalize_inventory_snapshot.py  # Tier 3.5 inventory CDM translator
│           └── normalize_inventory_snapshot.sql
│
├── tests/
│   ├── run_odoo_crm_crud_and_normalize.py    # E2E test: create → normalize
│   ├── run_odoo_crm_crud_update_delete.py    # CRUD operations test
│   ├── test_tier4_chain.py                   # Tier 4 analyzer test
│   ├── test_tier_e2e.py                      # Full Tier 3→5 sample pipeline
│   ├── test_live_odoo_integration.py         # Live Odoo integration test
│   └── cleanup_crm_test_leads.py             # Delete test data
│
└── samples/
    └── odoo_getset_lead_insert.sql           # Example recipe registration (reference)
```

---

## Setup: Get It Running

### Prerequisites
- Docker & Docker Compose
- Python 3.9+
- PostgreSQL client (for direct DB access; optional)

### 1. Create and activate a Python virtual environment

```bash
python -m venv .venv
# Windows PowerShell
.\.venv\Scripts\Activate.ps1
# Windows cmd
.\.venv\Scripts\activate.bat
# macOS / Linux
source .venv/bin/activate
```

### 2. Install Python dependencies

```bash
pip install --upgrade pip
pip install -r requirements.txt
```

### 3. Start the Docker stack

```bash
docker-compose up -d
```

This starts:
- **Odoo** on `http://localhost:8069` (user: `admin`, password: `admin`)
- **PostgreSQL** on `localhost:5432` (user: `hyve_admin`, password: `hyve_kitchen`)

### 4. Verify the app is running

Open a browser and visit:
- `http://localhost:8069`

Log in with the Odoo credentials shown above.

### 5. Live Odoo integration and tests

Run the basic Tier 3/Tier 3.5 verification first:
```bash
python tests/run_odoo_crm_crud_and_normalize.py
```

Then run the full sample-mode pipeline:
```bash
python tests/test_tier_e2e.py
```

If your Odoo demo user has inventory permissions, run the live Odoo pipeline test:
```bash
python tests/test_live_odoo_integration.py
```

If the Tier 3 inventory getter hits Odoo ACL restrictions, it will fall back to sample inventory and continue the pipeline so the rest of the analytics still works.

### 6. Run the main tests

```bash
python tests/run_odoo_crm_crud_and_normalize.py
```

This validates the Tier 3 and Tier 3.5 flow.

### 7. Run the Tier 4 analyzer test

```bash
python tests/test_tier4_chain.py --mode sample
```

If Odoo is available and recipe modules are importable, run the full chain:

```bash
python tests/test_tier4_chain.py --mode chain
```

### 8. Clean up test data

```bash
python tests/cleanup_crm_test_leads.py
```

Expected output for the basic verification test:
```
✓ Created lead: Allan Abendanio (ID: 42)
✓ Normalized to CommonCustomerProfile
✓ Lead retrieved via search
```

---

## How to Use: Step-by-Step

### Example: Analyze a customer's profile

```python
import sys
sys.path.insert(0, '../recipes')

from odoo.crm.odoo_crm_crud import run as crud_run
from _normalizers.CommonCustomerProfile.normalize_customer_profile import run as normalize_run
from odoo.crm.analyze_customer_profile_summary import run as analyze_run

# Step 1: Fetch raw lead from Odoo (Tier 3)
crud_result = crud_run({
    "odoo_base_url": "http://localhost:8069",
    "odoo_db": "odoo",
    "odoo_uid": 2,
    "odoo_password": "admin",
    "action": "read",
    "lead_id": 42
})

raw_lead = crud_result["data"]["lead"]

# Step 2: Normalize to CDM (Tier 3.5)
normalize_result = normalize_run({
    "raw_lead": raw_lead,
    "source_system": "odoo"
})

normalized_profile = normalize_result["data"]["normalized_profile"]

# Step 3: Analyze for insights (Tier 4)
analyze_result = analyze_run({
    "customer_profile": normalized_profile
})

print(f"Risk Score: {analyze_result['data']['risk_score']}")
print(f"Engagement Tier: {analyze_result['data']['engagement_tier']}")
print(f"Narrative: {analyze_result['data']['risk_narrative']}")
```

---

## Phase 2 Recipe Registration

Each recipe is registered in the `cookbook_recipe` table with metadata:

### Tier 3 fields (odoo_crm_crud)
```sql
tier = 'tier3'
cache_scope = 'tenant'
cdm_output_type = NULL          -- raw, unstructured output
cdm_input_types_csv = NULL
invalidates_cache_csv = 'norm:customer_profile:*,norm:customer_360:*'
```

### Tier 3.5 fields (normalize_customer_profile)
```sql
tier = 'tier3.5'
cache_scope = 'tenant'
cdm_output_type = 'CommonCustomerProfile'
cdm_input_types_csv = NULL       -- calls Tier 3 directly, not CDM
```

### Tier 4 fields (analyze_customer_profile_summary)
```sql
tier = 'tier4'
cache_scope = 'tenant'
cdm_output_type = 'CustomerProfileSummary'   -- output type
cdm_input_types_csv = 'CommonCustomerProfile'  -- consumes this CDM
```

### Tier 5 fields (predict_customer_ltv)
```sql
tier = 'tier5'
cache_scope = 'session'
cdm_output_type = 'CustomerLTVProjection'
cdm_input_types_csv = 'CustomerProfileSummary,CommonTransaction'
```

Tier 5 recipes are session-scoped predictive or simulation recipes. They consume analytics output from Tier 4 plus normalized transaction or inventory data, and they do not write back to the source system.

To verify the Tier 5 prediction logic, run:

```bash
python tests/test_tier5_predict_customer_ltv.py
```

---

## Inventory Module (Tier 3 → 4 → 5 Chain)

A complete example inventory analysis and simulation chain:

### Tier 3: odoo_get_inventory
Fetches raw inventory from Odoo stock module (sample-mode stub available).

### Tier 3.5: normalize_inventory_snapshot  
Transforms raw inventory into `CommonInventorySnapshot` CDM with qty_available, qty_reserved, qty_on_order, reorder_point.

### Tier 4: analyze_inventory_gaps
Analyzes normalized inventory and identifies products below reorder point. Enables purchasing decisions.

### Tier 5: simulate_inventory_change
Applies hypothetical qty deltas to inventory in-memory (what-if analysis). Session-scoped; never writes to Odoo. Core of the June 13 demo.

To run the end-to-end inventory simulation test:

```bash
python tests/test_tier5_simulate_inventory_change.py
```

This verifies:
1. Normalizer loads sample inventory via Tier 3 getter
2. Simulator applies a qty delta
3. Analyzer detects gaps on the modified snapshot

---

## Running Tests

### Prepare the environment

1. Start the Docker stack:

```bash
docker-compose up -d
```

2. Install Python dependencies:

```bash
pip install -r requirements.txt
```

3. Run tests from the repo root; the `tests/` scripts assume the current working directory is the project root.

### Test Tier 3 CRUD

```bash
python tests/run_odoo_crm_crud_and_normalize.py
```

What it does:
- Creates a test lead in Odoo
- Reads the lead back
- Verifies normalization works for the raw payload
- Confirms search behavior

### Test Tier 3.5 Normalizer

The same script also validates the normalizer output.

```bash
python tests/run_odoo_crm_crud_and_normalize.py
```

### Test Tier 4 Analyzer

#### Standalone sample test (no Odoo required)

```bash
python tests/test_tier4_chain.py --mode sample
```

This verifies the Tier 4 analyzer logic using a hard-coded `CommonCustomerProfile` sample.

#### Full chain test (requires Odoo and valid recipe imports)

```bash
python tests/test_tier4_chain.py --mode chain
```

This exercises the full flow:
- Tier 3 CRUD
- Tier 3.5 normalization
- Tier 4 analytics

#### Default test mode

```bash
python tests/test_tier4_chain.py
```

This runs both the sample and full chain modes; if the local Odoo/Tier 3 modules are not available, the chain portion will skip safely.

### Clean up test data

```bash
python tests/cleanup_crm_test_leads.py
```

This removes test leads created by the CRUD tests.

---

## Git Workflow

After you make changes, use these commands to commit and push them:

```bash
git status
git add -A
git commit -m "<describe your changes>"
git push origin main
```

If your branch is behind remote, run:

```bash
git pull origin main
```

Then rerun the push command.

---

## Common Workflows

### Add a new customer

```python
result = crud_run({
    "odoo_base_url": "http://localhost:8069",
    "odoo_db": "odoo",
    "odoo_uid": 2,
    "odoo_password": "admin",
    "action": "create",
    "lead_name": "Jane Doe",
    "lead_email": "jane@example.com",
    "lead_phone": "+1-555-9999"
})
print(f"Created lead ID: {result['data']['lead_id']}")
```

### Search for leads

```python
result = crud_run({
    "action": "search",
    "lead_email": "jane@example.com"
})
leads = result["data"]["leads"]
for lead in leads:
    print(f"Found: {lead['name']} ({lead['id']})")
```

### Get analytics for a lead

```python
# Step 1: Read lead
lead_result = crud_run({"action": "read", "lead_id": 42, ...})
lead = lead_result["data"]["lead"]

# Step 2: Normalize
norm_result = normalize_run({"raw_lead": lead, ...})
profile = norm_result["data"]["normalized_profile"]

# Step 3: Analyze
analysis = analyze_run({"customer_profile": profile})
print(f"Risk: {analysis['data']['risk_score']}, Tier: {analysis['data']['engagement_tier']}")
```

---

## For New Developers: Understanding the Tiers

### Why three tiers?

1. **Tier 3 (Raw Access)**: Keeps knowledge of Odoo local. Easy to swap Odoo for Salesforce; just rewrite Tier 3.
2. **Tier 3.5 (Normalization)**: Other analyzers don't care about system details. They consume CDM only.
3. **Tier 4+ (Analytics)**: Pure business logic. No system-specific code.

### Key principle: Data flows, not calls

```
User Request
    ↓
[Tier 3: CRUD] ← Knows Odoo JSON-RPC
    ↓ raw lead {id, name, email_from, phone, ...}
[Tier 3.5: Normalizer] ← Transforms to CDM
    ↓ CommonCustomerProfile {customer_id, name, email, phone, ...}
[Tier 4: Analyzer] ← Consumes CDM only
    ↓ Analytics {risk_score, engagement_tier, ...}
User sees insights
```

### Adding a new Tier 4 analyzer

1. Create `recipes/odoo/crm/analyze_*.py`.
2. Declare in `.sql`:
   - `tier = 'tier4'`
   - `cdm_input_types_csv = 'CommonCustomerProfile'` (or whatever CDM you consume)
   - `cdm_output_type = 'YourAnalyticsType'`
3. Import normalized profile from upstream.
4. Compute your analytics.
5. Return standard envelope: `{status, http_status, data, user_message, system_message}`

---

## Troubleshooting

### Odoo not responding
```bash
docker ps | grep odoo
docker logs hyve-kitchen-web-1
```

### Python import errors
Ensure your `PYTHONPATH` includes `recipes/`:
```bash
export PYTHONPATH="${PYTHONPATH}:$(pwd)/recipes"
python tests/run_odoo_crm_crud_and_normalize.py
```

### PostgreSQL connection refused
```bash
docker exec hyve-kitchen-db-1 psql -U hyve_admin -d hyve_kitchen_test -c "SELECT 1;"
```

### Test data leftover
```bash
cd tests
python cleanup_crm_test_leads.py
```

---

## Next Steps

1. **Add more normalizers**: E.g., `normalize_transaction_history` for order data.
2. **Add more analyzers**: E.g., `analyze_churn_signals`, `analyze_customer_ltv`.
3. **Test the full chain**: Each tier depends on its upstream; validate caching and invalidation.
4. **Integrate with cook.py**: Once the Hyve backend recipe orchestration engine is ready, recipes will auto-chain.

---

## References

- **Phase 2 Guide**: See `analytics_recipe_author_guide.txt` for recipe authoring conventions.
- **Brainstorm Doc**: See `hyve_phase2_brainstorm_v2.docx` for architectural rationale.
- **Odoo API**: [Odoo JSON-RPC Docs](https://www.odoo.com/documentation/17.0/developer.html)

---

## Questions?

For architecture questions, refer to the **Phase 2 brainstorm document**.
For code issues, check test output or add debug prints to recipe `run(vars)` functions.
