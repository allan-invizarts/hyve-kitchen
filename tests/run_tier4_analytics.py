"""Run all Tier 4 analyzers against CDM fixtures."""

import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from recipes.odoo.analytics._registry import FIXTURE_MAP, RUNNERS, vars_from_fixtures


def main():
    for recipe_name in FIXTURE_MAP:
        result = RUNNERS[recipe_name](vars_from_fixtures(recipe_name))
        print(f"\n=== {recipe_name} ===")
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
