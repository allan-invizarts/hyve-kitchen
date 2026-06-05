import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from recipes import odoo_crm_crud


def main():
    base_vars = {
        "odoo_base_url": "http://localhost:8069",
        "odoo_db": "hyve_kitchen",
        "odoo_uid": 7,
        "odoo_password": "Test12345!",
    }

    print("Creating a test CRM lead...")
    create_vars = dict(
        base_vars,
        action="create",
        lead_name="CRUD Update/Delete Test",
        lead_email="crud-update-delete@hyve.ai",
        lead_phone="555-0100",
        face_hash="",
    )
    create_result = odoo_crm_crud.run(create_vars)
    print(json.dumps(create_result, indent=2))

    if create_result.get("status") != "SUCCESS":
        print("Create failed; aborting test.")
        return

    lead_id = create_result["data"]["lead_id"]
    print(f"Lead created with id={lead_id}\n")

    print("Updating the lead name and phone...")
    update_vars = dict(
        base_vars,
        action="update",
        lead_id=lead_id,
        lead_name="CRUD Updated Name",
        lead_phone="555-1212",
    )
    update_result = odoo_crm_crud.run(update_vars)
    print(json.dumps(update_result, indent=2))

    print("Reading the updated lead...")
    read_vars = dict(base_vars, action="read", lead_id=lead_id)
    read_result = odoo_crm_crud.run(read_vars)
    print(json.dumps(read_result, indent=2))

    print("Deleting the lead...")
    delete_vars = dict(base_vars, action="delete", lead_id=lead_id)
    delete_result = odoo_crm_crud.run(delete_vars)
    print(json.dumps(delete_result, indent=2))


if __name__ == "__main__":
    main()
