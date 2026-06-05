import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from recipes._normalizers.CommonCustomerProfile.normalize_customer_profile import run


def main():
    sample_lead = {
        "id": 42,
        "name": "Ana Lopez",
        "email_from": "ana.lopez@example.com",
        "phone": "+1-808-555-1234",
        "x_hyve_face_hash": "FH-ABC-123",
        "tag_ids": ["vip", "repeat_customer"],
        "x_loyalty_tier": "gold",
        "x_loyalty_points": 1240,
        "create_date": "2025-11-01T13:20:00Z",
        "write_date": "2026-06-04T09:12:00Z",
    }

    vars = {
        "odoo_lead": sample_lead,
    }

    result = run(vars)
    print("Input lead:")
    print(json.dumps(sample_lead, indent=2))
    print("\nNormalized result:")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
