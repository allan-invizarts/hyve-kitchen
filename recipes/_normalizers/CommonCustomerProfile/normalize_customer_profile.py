"""
Tier 3.5 normalizer: Convert raw Odoo lead payload into CommonCustomerProfile.
"""

import json
from typing import Any, Dict, List, Optional


def _first_nonempty(*values: Any) -> Optional[Any]:
    for value in values:
        if value is not None and value != "":
            return value
    return None


def _normalize_tags(tag_values: Any) -> List[str]:
    if tag_values is None:
        return []
    if isinstance(tag_values, str):
        return [tag_values]
    if isinstance(tag_values, dict):
        return [str(tag_values)]
    if isinstance(tag_values, list):
        normalized: List[str] = []
        for item in tag_values:
            if item is None:
                continue
            if isinstance(item, str):
                normalized.append(item)
            elif isinstance(item, dict):
                if "name" in item:
                    normalized.append(str(item["name"]))
                else:
                    normalized.append(json.dumps(item, ensure_ascii=False))
            else:
                normalized.append(str(item))
        return normalized
    return [str(tag_values)]


def _normalize_customer_profile(raw_lead: Dict[str, Any]) -> Dict[str, Any]:
    lead_id = raw_lead.get("id")
    customer_id = f"odoo:lead:{lead_id}" if lead_id is not None else None

    profile = {
        "customer_id": customer_id,
        "source_system": "odoo",
        "source_id": str(lead_id) if lead_id is not None else None,
        "name": _first_nonempty(raw_lead.get("name"), raw_lead.get("display_name")),
        "email": _first_nonempty(raw_lead.get("email_from"), raw_lead.get("email")),
        "phone": _first_nonempty(raw_lead.get("phone_mobile"), raw_lead.get("phone")),
        "face_hash": _first_nonempty(raw_lead.get("x_hyve_face_hash"), raw_lead.get("face_hash")),
        "tags": _normalize_tags(raw_lead.get("tag_ids") or raw_lead.get("tags")),
        "loyalty_tier": _first_nonempty(raw_lead.get("x_loyalty_tier"), raw_lead.get("loyalty_tier")),
        "loyalty_points": raw_lead.get("x_loyalty_points") or raw_lead.get("loyalty_points"),
        "created_at": _first_nonempty(raw_lead.get("create_date"), raw_lead.get("created_at")),
        "last_seen_at": _first_nonempty(raw_lead.get("write_date"), raw_lead.get("last_seen_at"), raw_lead.get("last_seen")),
    }

    # Keep output clean: remove keys that are still None.
    return {k: v for k, v in profile.items() if v is not None}


def _parse_lead_input(vars: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    if isinstance(vars.get("odoo_lead"), dict):
        return vars["odoo_lead"]

    if isinstance(vars.get("lead"), dict):
        return vars["lead"]

    data = vars.get("data")
    if isinstance(data, dict) and isinstance(data.get("lead"), dict):
        return data["lead"]

    lead_json = vars.get("odoo_lead_json")
    if isinstance(lead_json, str) and lead_json.strip():
        try:
            parsed = json.loads(lead_json)
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            return None

    return None


def run(vars: Dict[str, Any]) -> Dict[str, Any]:
    raw_lead = _parse_lead_input(vars)
    if raw_lead is None:
        return {
            "status": "MISSING_INPUT",
            "http_status": 400,
            "data": {},
            "user_message": "No raw Odoo lead data was provided.",
            "system_message": "normalize_customer_profile requires odoo_lead or lead input.",
        }

    try:
        profile = _normalize_customer_profile(raw_lead)
        if not profile.get("customer_id"):
            return {
                "status": "VALIDATION_ERROR",
                "http_status": 400,
                "data": {},
                "user_message": "The Odoo lead record is missing an ID.",
                "system_message": "normalize_customer_profile could not derive customer_id.",
            }
        return {
            "status": "SUCCESS",
            "http_status": 200,
            "data": profile,
            "user_message": "Customer profile normalized successfully.",
            "system_message": "Tier 3.5 normalization completed.",
        }
    except Exception as exc:
        return {
            "status": "UNKNOWN_ERROR",
            "http_status": 500,
            "data": {},
            "user_message": "An unexpected error occurred during normalization.",
            "system_message": str(exc),
        }
