"""Factory for Tier 4 recipe entrypoints."""

from __future__ import annotations

from typing import Any, Callable, Dict

from recipes.odoo.analytics._tier4_base import run_analyzer

AnalyzeFn = Callable[[Dict[str, Any]], Dict[str, Any]]
RunFn = Callable[[Dict[str, Any]], Dict[str, Any]]


def tier4_recipe(
    recipe_name: str,
    analyze: AnalyzeFn,
    *,
    error_message: str | None = None,
) -> RunFn:
    """Return the standard run(vars) entrypoint for a Tier 4 analyzer."""
    message = error_message or f"{recipe_name.replace('_', ' ')} failed."

    def run(vars: Dict[str, Any]) -> Dict[str, Any]:
        return run_analyzer(recipe_name, vars, analyze, error_message=message)

    run.__doc__ = f"Tier 4 recipe entrypoint for {recipe_name}."
    return run
