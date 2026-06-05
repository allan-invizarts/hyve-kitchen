"""CDM payload validation against config/cdm schemas."""

from __future__ import annotations

from typing import Any, Dict, List, Tuple

from recipes._cdm.schema import get_type, type_cardinality


def _check_field(field: Dict[str, Any], value: Any) -> List[str]:
    name = field.get("name", "?")
    expected = field.get("type", "string")

    if value is None:
        return [f"{name}: required field is missing"] if field.get("required") else []

    type_checks = {
        "string": lambda v: isinstance(v, str),
        "int": lambda v: isinstance(v, int) and not isinstance(v, bool),
        "float": lambda v: isinstance(v, (int, float)),
        "bool": lambda v: isinstance(v, bool),
        "list": lambda v: isinstance(v, list),
        "object": lambda v: isinstance(v, dict),
    }
    if expected in type_checks and not type_checks[expected](value):
        return [f"{name}: expected {expected}, got {type(value).__name__}"]
    return []


def _field_errors(obj: Dict[str, Any], type_name: str, *, strict: bool) -> List[str]:
    schema = get_type(type_name)
    errors: List[str] = []
    for field in schema.get("fields") or []:
        errors.extend(_check_field(field, obj.get(field["name"])))
    if strict:
        allowed = {f["name"] for f in schema.get("fields") or []}
        errors.extend(
            f"{type_name}: unexpected field '{key}'"
            for key in obj
            if key not in allowed
        )
    return errors


def validate_object(
    obj: Any,
    type_name: str,
    *,
    strict: bool = False,
) -> Tuple[bool, List[str]]:
    if not isinstance(obj, dict):
        return False, [f"{type_name}: expected object, got {type(obj).__name__}"]
    errors = _field_errors(obj, type_name, strict=strict)
    return len(errors) == 0, errors


def validate_list(
    items: Any,
    type_name: str,
    *,
    strict: bool = False,
) -> Tuple[bool, List[str]]:
    if not isinstance(items, list):
        return False, [f"{type_name}: expected list, got {type(items).__name__}"]

    errors: List[str] = []
    for index, item in enumerate(items):
        ok, item_errors = validate_object(item, type_name, strict=strict)
        if not ok:
            errors.extend(f"[{index}] {err}" for err in item_errors)
    return len(errors) == 0, errors


def validate_transaction(tx: Dict[str, Any], *, strict: bool = False) -> Tuple[bool, List[str]]:
    ok, errors = validate_object(tx, "CommonTransaction", strict=strict)
    if ok and isinstance(tx.get("items"), list):
        item_ok, item_errors = validate_list(tx["items"], "LineItem", strict=strict)
        if not item_ok:
            errors.extend(item_errors)
            ok = False
    return ok, errors


def validate_transactions(items: Any, *, strict: bool = False) -> Tuple[bool, List[str]]:
    if not isinstance(items, list):
        return False, ["CommonTransaction: expected list"]

    errors: List[str] = []
    for index, tx in enumerate(items):
        if not isinstance(tx, dict):
            errors.append(f"[{index}] expected object")
            continue
        ok, tx_errors = validate_transaction(tx, strict=strict)
        if not ok:
            errors.extend(f"[{index}] {err}" for err in tx_errors)
    return len(errors) == 0, errors


def validate_cdm(type_name: str, value: Any, *, strict: bool = False) -> Tuple[bool, List[str]]:
    if type_name == "CommonTransaction":
        return validate_transactions(value, strict=strict)
    if type_cardinality(type_name) == "object":
        return validate_object(value, type_name, strict=strict)
    return validate_list(value, type_name, strict=strict)
