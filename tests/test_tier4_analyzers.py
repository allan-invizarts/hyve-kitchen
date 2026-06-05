"""Unit tests for Tier 4 analyzers — output contracts."""

import copy
import os
import sys
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from recipes.odoo.analytics._registry import FIXTURE_MAP, RUNNERS, vars_from_fixtures


class TestTier4Analyzers(unittest.TestCase):
    def _run(self, recipe_name: str, vars_override=None):
        return RUNNERS[recipe_name](vars_override or vars_from_fixtures(recipe_name))

    def test_all_recipes_success(self):
        for recipe_name in FIXTURE_MAP:
            with self.subTest(recipe=recipe_name):
                self.assertEqual(self._run(recipe_name)["status"], "SUCCESS")

    def test_analyze_spend_trend_missing_input(self):
        self.assertEqual(RUNNERS["analyze_spend_trend"]({})["status"], "MISSING_INPUT")

    def test_spend_trend_contract(self):
        data = self._run("analyze_spend_trend")["data"]
        for key in ("period", "buckets", "total_current", "total_prior", "delta_pct", "trend"):
            self.assertIn(key, data)

    def test_inventory_gaps_contract(self):
        data = self._run("analyze_inventory_gaps")["data"]
        self.assertIn("as_of", data)
        self.assertGreater(len(data["gaps"]), 0)
        row = data["gaps"][0]
        for key in (
            "product_id",
            "qty_available",
            "sales_velocity_per_day",
            "severity",
        ):
            self.assertIn(key, row)
        self.assertNotIn("risk", row)

    def test_inventory_gaps_sim_override(self):
        vars_payload = vars_from_fixtures("analyze_inventory_gaps")
        sim_snapshots = copy.deepcopy(vars_payload["inventory_snapshots"])
        for snap in sim_snapshots:
            if snap["product_id"] == "PROD-B":
                snap["qty_available"] = 50.0
        vars_payload["inventory_snapshots"] = sim_snapshots
        prod_b = next(
            g for g in self._run("analyze_inventory_gaps", vars_payload)["data"]["gaps"]
            if g["product_id"] == "PROD-B"
        )
        self.assertIn(prod_b["severity"], ("ok", "warning"))

    def test_churn_score_contract(self):
        data = self._run("analyze_churn_signals")["data"]
        self.assertIn("score", data)
        self.assertIn("risk_level", data)
        self.assertIn(data["risk_level"], ("high", "medium", "low"))
        self.assertIsInstance(data["risk_factors"], list)
        self.assertGreaterEqual(data["score"], 0)
        self.assertLessEqual(data["score"], 100)
        self.assertNotIn("trend", data)

    def test_ltv_projection_contract(self):
        data = self._run("analyze_customer_ltv")["data"]
        for key in ("annualized_ltv", "currency", "trend", "confidence"):
            self.assertIn(key, data)
        self.assertEqual(data["currency"], "USD")
        self.assertNotIn("annualized_value", data)


if __name__ == "__main__":
    unittest.main()
