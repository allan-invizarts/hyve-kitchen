"""
Resolve Tier 4 recipe inputs and load test fixtures.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List

from recipes._cdm.schema import config_root

_CONFIG_ROOT = config_root()
_VAR_MAPPING_PATH = _CONFIG_ROOT / "tier4_var_mapping.json"
_FIXTURES_ROOT = Path(__file__).resolve().parents[2] / "tests" / "fixtures" / "cdm"
_VAR_MAPPING_CACHE: Dict[str, Any] | None = None


def _var_mapping() -> Dict[str, Any]:
    global _VAR_MAPPING_CACHE
    if _VAR_MAPPING_CACHE is None:
        with _VAR_MAPPING_PATH.open(encoding="utf-8") as handle:
            _VAR_MAPPING_CACHE = json.load(handle)
    return _VAR_MAPPING_CACHE


def recipe_input_types(recipe_name: str) -> List[str]:
    return list((_var_mapping().get(recipe_name, {}).get("inputs") or {}).keys())


def resolve_tier4_inputs(recipe_name: str, vars: Dict[str, Any]) -> Dict[str, Any]:
    inputs = (_var_mapping().get(recipe_name) or {}).get("inputs")
    if not inputs:
        raise KeyError(f"No tier4 var mapping for recipe: {recipe_name}")

    resolved: Dict[str, Any] = {}
    for type_name, var_key in inputs.items():
        if var_key in vars:
            resolved[type_name] = vars[var_key]
        elif type_name in vars:
            resolved[type_name] = vars[type_name]
    return resolved


def load_fixture(name: str) -> Any:
    path = _FIXTURES_ROOT / name
    if not path.exists():
        raise FileNotFoundError(path)
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)
