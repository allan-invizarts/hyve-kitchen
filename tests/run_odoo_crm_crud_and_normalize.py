import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from recipes import odoo_crm_crud
from recipes._normalizers.CommonCustomerProfile.normalize_customer_profile import run as normalize_run


def main():
    vars = {
        "odoo_base_url": "http://localhost:8069",
        "odoo_db": "hyve_kitchen",
        "odoo_uid": 7,
        "odoo_password": "Test12345!",
        "action": "create",
        "lead_name": "CRUD Normalize Test",
        "lead_email": f"crud-normalize-{__import__('uuid').uuid4().hex[:8]}@hyve.ai",
        "lead_phone": "",
        "face_hash": "",
    }

    print("Running Odoo CRM CRUD create action...")
    result = odoo_crm_crud.run(vars)
    print(json.dumps(result, indent=2))

    if result.get("status") != "SUCCESS" or not result.get("data"):
        print("CRUD create failed; aborting normalization.")
        return

    lead = result["data"].get("lead")
    if not isinstance(lead, dict) or not lead.get("id"):
        print("Invalid lead returned from CRUD create; aborting normalization.")
        return

    print("\nRunning normalizer on the lead...")
    norm_result = normalize_run({"odoo_lead": lead})
    print(json.dumps(norm_result, indent=2))


if __name__ == "__main__":
    main()
