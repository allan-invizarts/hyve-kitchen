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
    url = f"{base_vars['odoo_base_url'].rstrip('/')}/jsonrpc"
    names = [
        "CRUD Normalize Test",
        "CRUD test",
        "Mock Normalize Lead",
    ]
    deleted = []

    for name in names:
        domain = [[("name", "ilike", name)]]
        print(f"Searching for leads matching '{name}'...")
        leads = odoo_crm_crud._json_rpc(
            url,
            "object",
            "execute_kw",
            base_vars["odoo_db"],
            base_vars["odoo_uid"],
            base_vars["odoo_password"],
            "crm.lead",
            "search_read",
            domain,
            {"fields": ["id", "name", "email_from", "phone"], "limit": 100},
        )
        if not leads:
            print("  none found")
            continue
        for lead in leads:
            lead_name = lead.get("name", "")
            if name.lower() in lead_name.lower():
                print(f"  deleting lead {lead['id']}: {lead_name}")
                try:
                    success = odoo_crm_crud._json_rpc(
                        url,
                        "object",
                        "execute_kw",
                        base_vars["odoo_db"],
                        base_vars["odoo_uid"],
                        base_vars["odoo_password"],
                        "crm.lead",
                        "unlink",
                        [[lead["id"]]],
                    )
                    deleted.append((lead["id"], lead_name, success))
                except Exception as exc:
                    print(f"  failed to delete lead {lead['id']}: {exc}")
    print("\nDeleted leads:")
    print(json.dumps(deleted, indent=2))


if __name__ == "__main__":
    main()
