"""Offline integration of the actual shipped templates, never a TD query runner."""
import importlib.util
import json
from pathlib import Path
import re
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('validate_project', ROOT / 'scripts/validate_project.py')
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class TemplateIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name).resolve() / 'project'
        shutil.copytree(ROOT / 'templates/project', self.project)
        self.cfg_path = self.project / 'config/project.json'
        self.cfg = json.loads(self.cfg_path.read_text())
        self.cfg.update(configured=True, project_name='offline_fixture', output_database='analytics', web_table='source.web')
        self.cfg_path.write_text(json.dumps(self.cfg))
        path = self.project / 'queries/00_web.sql'
        text = path.read_text()
        expressions = {'member_id_expr': "'member'", 'is_login_expr': 'TRUE', 'is_purchase_expr': 'FALSE',
                       'order_id_expr': 'NULL', 'order_total_expr': 'NULL', 'currency_expr': "'JPY'"}
        for name, expression in expressions.items():
            text = text.replace('REPLACE_ME_' + name, expression)
        path.write_text(text)

    def test_actual_web_mode_compiles_with_disabled_optional_adapters(self):
        self.assertEqual(VALIDATOR.validate(self.project, compile_config=True), [])
        params = (self.project / 'config/params.yml').read_text()
        self.assertIn('ad_costs_enabled: false', params)
        self.assertIn('config_sha256:', params)
        self.assertEqual(VALIDATOR.validate(self.project), [])

    def test_enabled_costs_require_mapping(self):
        self.cfg['ad_costs_enabled'] = True
        self.cfg_path.write_text(json.dumps(self.cfg))
        errors = VALIDATOR.validate(self.project, compile_config=True)
        self.assertTrue(any('00_costs.sql' in error for error in errors))

    def test_separate_orders_require_mapping(self):
        self.cfg['purchase_mode'] = 'separate'
        self.cfg_path.write_text(json.dumps(self.cfg))
        errors = VALIDATOR.validate(self.project, compile_config=True)
        self.assertTrue(any('00_orders_separate.sql' in error for error in errors))

    def test_sql_is_select_only_for_create_table_operator(self):
        for path in (self.project / 'queries').glob('*.sql'):
            with self.subTest(file=path.name):
                sql = VALIDATOR.active_sql(path.read_text()).strip()
                self.assertRegex(sql, r'^(WITH|SELECT)\b')
                self.assertNotRegex(sql, r'(?i)\b(CREATE TABLE|DROP TABLE|INSERT INTO|DELETE FROM)\b')

    def test_occurrences_are_not_collapsed_by_source_before_lookback(self):
        sql = (self.project / 'queries/40_touches.sql').read_text()
        self.assertIn('PARTITION BY s.session_key, e.event_key', sql)
        self.assertNotIn('PARTITION BY s.session_key, e.source', sql)
        aggregate = (self.project / 'queries/71_inflow.sql').read_text()
        self.assertIn('SELECT DISTINCT td_client_id, source, medium, campaign, content, term', aggregate)

    def test_web_refires_do_not_move_purchase_after_later_login(self):
        sql = (self.project / 'queries/50_orders_web.sql').read_text()
        self.assertIn('MIN(event_time) OVER (PARTITION BY order_id) AS order_time', sql)

    def test_temporal_ownership_precedes_cohort_filter(self):
        sql = (self.project / 'queries/60_order_credit.sql').read_text()
        self.assertIn('m.observed_time < o.order_time', sql)
        self.assertNotIn('in_cohort', sql)
        lookback = (self.project / 'queries/61_lookback.sql').read_text()
        self.assertIn('t.touch_time < oc.order_time', lookback)
        self.assertIn('t.session_first_login_time < oc.order_time', lookback)

    def test_qa_numeric_gate_contract(self):
        sql = (self.project / 'queries/80_qa.sql').read_text()
        self.assertIn('CARDINALITY(hard_error_list) AS hard_errors', sql)
        self.assertIn("ARRAY_JOIN(hard_error_list, ',') AS hard_error_codes", sql)
        workflow = (self.project / 'ad_purchase_analytics.dig').read_text()
        self.assertIn('SELECT hard_errors', workflow)
        self.assertIn('td.last_results.hard_errors > 0', workflow)


if __name__ == '__main__':
    unittest.main()
