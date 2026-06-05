"""CDM schema loading from config/ (no validation — avoids import cycles)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, Optional

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None  # type: ignore

_CONFIG_ROOT = Path(__file__).resolve().parents[2] / "config"
_MANIFEST_PATH = _CONFIG_ROOT / "cdm_manifest.json"

_TYPE_CACHE: Dict[str, Dict[str, Any]] = {}
_MANIFEST_CACHE: Optional[Dict[str, Any]] = None


def _parse_simple_yaml(text: str) -> Dict[str, Any]:
    root: Dict[str, Any] = {}
    current_list_key: Optional[str] = None
    current_item: Optional[Dict[str, Any]] = None

    def flush_item() -> None:
        nonlocal current_item, current_list_key
        if current_item is not None and current_list_key is not None:
            root[current_list_key].append(current_item)
            current_item = None

    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if line.startswith("  - "):
            flush_item()
            current_item = {}
            item_body = line[4:].strip()
            if ":" in item_body:
                key, value = item_body.split(":", 1)
                current_item[key.strip()] = _coerce_scalar(value.strip())
            continue
        if line.startswith("    ") and current_item is not None:
            key, value = line.strip().split(":", 1)
            current_item[key.strip()] = _coerce_scalar(value.strip())
            continue
        flush_item()
        current_list_key = None
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key, value = key.strip(), value.strip()
        if not value:
            current_list_key = key
            root[key] = []
        else:
            root[key] = _coerce_scalar(value)

    flush_item()
    return root


def _coerce_scalar(value: str) -> Any:
    if value in ("true", "True"):
        return True
    if value in ("false", "False"):
        return False
    if value.isdigit():
        return int(value)
    return value


def _load_schema_file(path: Path) -> Dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    if yaml is not None:
        return yaml.safe_load(text) or {}
    return _parse_simple_yaml(text)


def _manifest() -> Dict[str, Any]:
    global _MANIFEST_CACHE
    if _MANIFEST_CACHE is None:
        with _MANIFEST_PATH.open(encoding="utf-8") as handle:
            _MANIFEST_CACHE = json.load(handle)
    return _MANIFEST_CACHE


def _manifest_entry(type_name: str) -> Dict[str, Any]:
    for section in ("types", "outputs"):
        meta = (_manifest().get(section) or {}).get(type_name)
        if meta:
            return meta
    raise KeyError(f"Unknown CDM or output type: {type_name}")


def get_type(type_name: str) -> Dict[str, Any]:
    if type_name not in _TYPE_CACHE:
        meta = _manifest_entry(type_name)
        _TYPE_CACHE[type_name] = _load_schema_file(_CONFIG_ROOT / meta["path"])
    return _TYPE_CACHE[type_name]


def type_cardinality(type_name: str) -> str:
    return _manifest_entry(type_name).get("cardinality", "object")


def config_root() -> Path:
    return _CONFIG_ROOT
