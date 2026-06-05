-- cookbook_recipe_dependency rows (requires V105 table from hyve-blackbox PR-1)
BEGIN;

INSERT INTO cookbook_recipe_dependency (id, recipe_id, depends_on_recipe_id, dependency_type, created_by)
SELECT generate_custom_guid('DEP'),
       (SELECT id FROM cookbook_recipe WHERE name = 'analyze_spend_trend'),
       (SELECT id FROM cookbook_recipe WHERE name = 'normalize_transaction_history'),
       'data', 'tier4-generator'
WHERE EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'analyze_spend_trend')
  AND EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'normalize_transaction_history')
  AND NOT EXISTS (
      SELECT 1 FROM cookbook_recipe_dependency d
      JOIN cookbook_recipe r ON r.id = d.recipe_id
      JOIN cookbook_recipe u ON u.id = d.depends_on_recipe_id
      WHERE r.name = 'analyze_spend_trend' AND u.name = 'normalize_transaction_history'
  );

INSERT INTO cookbook_recipe_dependency (id, recipe_id, depends_on_recipe_id, dependency_type, created_by)
SELECT generate_custom_guid('DEP'),
       (SELECT id FROM cookbook_recipe WHERE name = 'analyze_inventory_gaps'),
       (SELECT id FROM cookbook_recipe WHERE name = 'normalize_transaction_history'),
       'data', 'tier4-generator'
WHERE EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'analyze_inventory_gaps')
  AND EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'normalize_transaction_history')
  AND NOT EXISTS (
      SELECT 1 FROM cookbook_recipe_dependency d
      JOIN cookbook_recipe r ON r.id = d.recipe_id
      JOIN cookbook_recipe u ON u.id = d.depends_on_recipe_id
      WHERE r.name = 'analyze_inventory_gaps' AND u.name = 'normalize_transaction_history'
  );

INSERT INTO cookbook_recipe_dependency (id, recipe_id, depends_on_recipe_id, dependency_type, created_by)
SELECT generate_custom_guid('DEP'),
       (SELECT id FROM cookbook_recipe WHERE name = 'analyze_inventory_gaps'),
       (SELECT id FROM cookbook_recipe WHERE name = 'normalize_inventory_snapshot'),
       'data', 'tier4-generator'
WHERE EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'analyze_inventory_gaps')
  AND EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'normalize_inventory_snapshot')
  AND NOT EXISTS (
      SELECT 1 FROM cookbook_recipe_dependency d
      JOIN cookbook_recipe r ON r.id = d.recipe_id
      JOIN cookbook_recipe u ON u.id = d.depends_on_recipe_id
      WHERE r.name = 'analyze_inventory_gaps' AND u.name = 'normalize_inventory_snapshot'
  );

INSERT INTO cookbook_recipe_dependency (id, recipe_id, depends_on_recipe_id, dependency_type, created_by)
SELECT generate_custom_guid('DEP'),
       (SELECT id FROM cookbook_recipe WHERE name = 'analyze_churn_signals'),
       (SELECT id FROM cookbook_recipe WHERE name = 'normalize_customer_profile'),
       'data', 'tier4-generator'
WHERE EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'analyze_churn_signals')
  AND EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'normalize_customer_profile')
  AND NOT EXISTS (
      SELECT 1 FROM cookbook_recipe_dependency d
      JOIN cookbook_recipe r ON r.id = d.recipe_id
      JOIN cookbook_recipe u ON u.id = d.depends_on_recipe_id
      WHERE r.name = 'analyze_churn_signals' AND u.name = 'normalize_customer_profile'
  );

INSERT INTO cookbook_recipe_dependency (id, recipe_id, depends_on_recipe_id, dependency_type, created_by)
SELECT generate_custom_guid('DEP'),
       (SELECT id FROM cookbook_recipe WHERE name = 'analyze_churn_signals'),
       (SELECT id FROM cookbook_recipe WHERE name = 'normalize_transaction_history'),
       'data', 'tier4-generator'
WHERE EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'analyze_churn_signals')
  AND EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'normalize_transaction_history')
  AND NOT EXISTS (
      SELECT 1 FROM cookbook_recipe_dependency d
      JOIN cookbook_recipe r ON r.id = d.recipe_id
      JOIN cookbook_recipe u ON u.id = d.depends_on_recipe_id
      WHERE r.name = 'analyze_churn_signals' AND u.name = 'normalize_transaction_history'
  );

INSERT INTO cookbook_recipe_dependency (id, recipe_id, depends_on_recipe_id, dependency_type, created_by)
SELECT generate_custom_guid('DEP'),
       (SELECT id FROM cookbook_recipe WHERE name = 'analyze_churn_signals'),
       (SELECT id FROM cookbook_recipe WHERE name = 'normalize_helpdesk_tickets'),
       'data', 'tier4-generator'
WHERE EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'analyze_churn_signals')
  AND EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'normalize_helpdesk_tickets')
  AND NOT EXISTS (
      SELECT 1 FROM cookbook_recipe_dependency d
      JOIN cookbook_recipe r ON r.id = d.recipe_id
      JOIN cookbook_recipe u ON u.id = d.depends_on_recipe_id
      WHERE r.name = 'analyze_churn_signals' AND u.name = 'normalize_helpdesk_tickets'
  );

INSERT INTO cookbook_recipe_dependency (id, recipe_id, depends_on_recipe_id, dependency_type, created_by)
SELECT generate_custom_guid('DEP'),
       (SELECT id FROM cookbook_recipe WHERE name = 'analyze_customer_ltv'),
       (SELECT id FROM cookbook_recipe WHERE name = 'normalize_transaction_history'),
       'data', 'tier4-generator'
WHERE EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'analyze_customer_ltv')
  AND EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'normalize_transaction_history')
  AND NOT EXISTS (
      SELECT 1 FROM cookbook_recipe_dependency d
      JOIN cookbook_recipe r ON r.id = d.recipe_id
      JOIN cookbook_recipe u ON u.id = d.depends_on_recipe_id
      WHERE r.name = 'analyze_customer_ltv' AND u.name = 'normalize_transaction_history'
  );

INSERT INTO cookbook_recipe_dependency (id, recipe_id, depends_on_recipe_id, dependency_type, created_by)
SELECT generate_custom_guid('DEP'),
       (SELECT id FROM cookbook_recipe WHERE name = 'analyze_customer_ltv'),
       (SELECT id FROM cookbook_recipe WHERE name = 'normalize_loyalty_status'),
       'data', 'tier4-generator'
WHERE EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'analyze_customer_ltv')
  AND EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'normalize_loyalty_status')
  AND NOT EXISTS (
      SELECT 1 FROM cookbook_recipe_dependency d
      JOIN cookbook_recipe r ON r.id = d.recipe_id
      JOIN cookbook_recipe u ON u.id = d.depends_on_recipe_id
      WHERE r.name = 'analyze_customer_ltv' AND u.name = 'normalize_loyalty_status'
  );

INSERT INTO cookbook_recipe_dependency (id, recipe_id, depends_on_recipe_id, dependency_type, created_by)
SELECT generate_custom_guid('DEP'),
       (SELECT id FROM cookbook_recipe WHERE name = 'analyze_customer_segment'),
       (SELECT id FROM cookbook_recipe WHERE name = 'normalize_transaction_history'),
       'data', 'tier4-generator'
WHERE EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'analyze_customer_segment')
  AND EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'normalize_transaction_history')
  AND NOT EXISTS (
      SELECT 1 FROM cookbook_recipe_dependency d
      JOIN cookbook_recipe r ON r.id = d.recipe_id
      JOIN cookbook_recipe u ON u.id = d.depends_on_recipe_id
      WHERE r.name = 'analyze_customer_segment' AND u.name = 'normalize_transaction_history'
  );

INSERT INTO cookbook_recipe_dependency (id, recipe_id, depends_on_recipe_id, dependency_type, created_by)
SELECT generate_custom_guid('DEP'),
       (SELECT id FROM cookbook_recipe WHERE name = 'analyze_store_session_metrics'),
       (SELECT id FROM cookbook_recipe WHERE name = 'normalize_kiosk_session'),
       'data', 'tier4-generator'
WHERE EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'analyze_store_session_metrics')
  AND EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'normalize_kiosk_session')
  AND NOT EXISTS (
      SELECT 1 FROM cookbook_recipe_dependency d
      JOIN cookbook_recipe r ON r.id = d.recipe_id
      JOIN cookbook_recipe u ON u.id = d.depends_on_recipe_id
      WHERE r.name = 'analyze_store_session_metrics' AND u.name = 'normalize_kiosk_session'
  );

COMMIT;