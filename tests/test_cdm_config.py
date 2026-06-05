"""Validate CDM fixtures against config/cdm YAML schemas."""

import os
import sys
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from recipes._cdm.loader import load_fixture  # noqa: E402
from recipes._cdm.validation import (  # noqa: E402
    validate_list,
    validate_object,
    validate_transactions,
)


class TestCdmConfig(unittest.TestCase):
    def test_customer_profile_fixture(self):
        ok, errs = validate_object(load_fixture("customer_profile.json"), "CommonCustomerProfile")
        self.assertTrue(ok, errs)

    def test_transactions_fixture(self):
        ok, errs = validate_transactions(load_fixture("transactions_90d.json"))
        self.assertTrue(ok, errs)

    def test_inventory_snapshot_fixture(self):
        ok, errs = validate_list(load_fixture("inventory_snapshot.json"), "CommonInventorySnapshot")
        self.assertTrue(ok, errs)

    def test_service_tickets_fixture(self):
        ok, errs = validate_list(load_fixture("service_tickets.json"), "CommonServiceTicket")
        self.assertTrue(ok, errs)

    def test_loyalty_status_fixture(self):
        ok, errs = validate_object(load_fixture("loyalty_status.json"), "CommonLoyaltyStatus")
        self.assertTrue(ok, errs)

    def test_kiosk_sessions_fixture(self):
        ok, errs = validate_list(load_fixture("kiosk_sessions.json"), "CommonKioskSession")
        self.assertTrue(ok, errs)

    def test_products_fixture(self):
        ok, errs = validate_list(load_fixture("products.json"), "CommonProduct")
        self.assertTrue(ok, errs)


if __name__ == "__main__":
    unittest.main()
