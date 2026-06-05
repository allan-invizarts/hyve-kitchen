"""Tier 4: analyze_store_session_metrics — aggregate kiosk session metrics."""

from __future__ import annotations

from collections import Counter
from typing import Any, Dict, List

from recipes._cdm.envelope import success
from recipes.odoo.analytics._recipe import tier4_recipe

RECIPE_NAME = "analyze_store_session_metrics"
_EMPTY = {
    "session_count": 0,
    "conversion_rate": 0.0,
    "top_intents": [],
    "avg_duration_seconds": 0.0,
}


def _analyze(resolved: Dict[str, Any]) -> Dict[str, Any]:
    sessions: List[Dict[str, Any]] = resolved["CommonKioskSession"]
    if not sessions:
        return success(_EMPTY, user_message="No kiosk sessions to analyze.")

    durations = [
        int(s["duration_seconds"])
        for s in sessions
        if isinstance(s.get("duration_seconds"), (int, float))
    ]
    intents = Counter(str(s["intent"]) for s in sessions if s.get("intent"))
    converted = sum(1 for s in sessions if s.get("converted"))
    count = len(sessions)

    return success(
        {
            "session_count": count,
            "conversion_rate": round(converted / count, 4),
            "top_intents": [{"intent": name, "count": n} for name, n in intents.most_common(5)],
            "avg_duration_seconds": round(sum(durations) / len(durations), 1) if durations else 0.0,
        }
    )


run = tier4_recipe(RECIPE_NAME, _analyze, error_message="Session metrics analysis failed.")
