"""Tier 4 recipe registry for tests and runners."""

from __future__ import annotations

import json
from importlib import import_module
from pathlib import Path
from typing import Any, Callable, Dict

from recipes._cdm.loader import load_fixture

_FIXTURE_CONFIG = Path(__file__).resolve().parents[3] / "config" / "tier4_test_fixtures.json"


def _load_fixture_map() -> Dict[str, Dict[str, str]]:
    with _FIXTURE_CONFIG.open(encoding="utf-8") as handle:
        return json.load(handle)


FIXTURE_MAP: Dict[str, Dict[str, str]] = _load_fixture_map()
RUNNERS: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]] = {
    name: import_module(f"recipes.odoo.analytics.{name}").run for name in FIXTURE_MAP
}


def vars_from_fixtures(recipe_name: str) -> Dict[str, Any]:
    return {key: load_fixture(path) for key, path in FIXTURE_MAP[recipe_name].items()}
