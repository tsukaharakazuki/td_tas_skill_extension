"""Offline dashboard contract tests. These do not validate TD SQL."""
import copy
import hashlib
import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('render_dashboard', ROOT / 'scripts/render_dashboard.py')
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


class DashboardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name).resolve() / 'project'
        shutil.copytree(ROOT / 'templates/project', self.project)
        self.cfg_path = self.project / 'config/project.json'
        self.config = json.loads(self.cfg_path.read_text())
        self.config['configured'] = True
        self.config['project_name'] = 'demo'
        self.config['output_database'] = 'analytics'
        self.config['web_table'] = 'source.web'
        self.cfg_path.write_text(json.dumps(self.config))
        self.data = json.loads((ROOT / 'examples/demo-data.json').read_text())
        self.bundle_path = self.project / 'data.json'

    def run_cli(self, demo=True, promote=False):
        self.bundle_path.write_text(json.dumps(self.data))
        args = ['--project', str(self.project), '--data', str(self.bundle_path)]
        if demo:
            args += ['--demo']
        if promote:
            args += ['--promote']
        return MOD.main(args)

    def production(self):
        self.data['demo'] = False
        self.data['manifest']['qa_passed'] = True
        self.data['manifest']['config_sha256'] = hashlib.sha256(self.cfg_path.read_bytes()).hexdigest()

    def test_demo_has_brand_and_no_scripts(self):
        self.assertEqual(self.run_cli(), 0)
        output = (self.project / 'dashboard_output/runs/1792500000_1/index.html').read_text()
        for expected in ('合成データ', 'Prepared by Treasure Data', 'tas-logo-horizontal', '--tas-primary-1', '200'):
            self.assertIn(expected, output)
        self.assertNotIn('<script', output.lower())
        self.assertNotIn('KPI 1', output)
        self.assertNotIn('ダッシュボードタイトル', output)

    def test_null_cost_disables_global_roas(self):
        self.assertIsNone(MOD.totals(self.data['cohort'])['roas_pct'])

    def test_roas_is_ratio_not_average(self):
        rows = copy.deepcopy(self.data['cohort'][:2])
        self.assertAlmostEqual(float(MOD.totals(rows)['roas_pct']), 120000 / 70000 * 100)

    def test_xss_label_is_escaped(self):
        self.data['cohort'][0]['campaign'] = '<img src=x onerror=alert(1)>'
        self.assertEqual(self.run_cli(), 0)
        output = (self.project / 'dashboard_output/runs/1792500000_1/index.html').read_text()
        self.assertIn('&lt;img', output)
        self.assertNotIn('<img src=x', output)

    def test_private_raw_fields_blocked(self):
        for field in ('td_client_id', 'member_id', 'order_id', 'url', 'email'):
            with self.subTest(field=field):
                self.data['cohort'][0][field] = 'private'
                self.assertEqual(self.run_cli(), 1)
                del self.data['cohort'][0][field]

    def test_truncation_blocked(self):
        self.data['manifest']['row_counts']['cohort'] = 4
        self.assertEqual(self.run_cli(), 1)

    def test_duplicate_grain_blocked(self):
        self.data['cohort'].append(copy.deepcopy(self.data['cohort'][0]))
        self.data['manifest']['row_counts']['cohort'] += 1
        self.assertEqual(self.run_cli(), 1)

    def test_bad_run_path_blocked(self):
        self.data['manifest']['run_id'] = '../bad'
        self.assertEqual(self.run_cli(), 1)

    def test_currency_blocked(self):
        self.data['cohort'][0]['currency'] = 'USD'
        self.assertEqual(self.run_cli(), 1)

    def test_nonfinite_blocked(self):
        self.data['cohort'][0]['sales'] = 'NaN'
        self.assertEqual(self.run_cli(), 1)

    def test_unpriced_sales_blocked(self):
        self.data['cohort'][0]['unpriced_orders'] = 1
        self.assertEqual(self.run_cli(), 1)

    def test_demo_cannot_promote(self):
        self.assertEqual(self.run_cli(promote=True), 1)
        self.assertFalse((self.project / 'dashboard_output/index.html').exists())

    def test_failed_qa_keeps_latest(self):
        self.production()
        self.assertEqual(self.run_cli(demo=False, promote=True), 0)
        original = (self.project / 'dashboard_output/index.html').read_bytes()
        self.data['qa']['hard_errors'] = 1
        self.data['manifest']['run_id'] = '1792500001_2'
        self.data['manifest']['observation_end'] += 1
        self.data['manifest']['attempt_id'] = 2
        self.assertEqual(self.run_cli(demo=False, promote=True), 1)
        self.assertEqual((self.project / 'dashboard_output/index.html').read_bytes(), original)

    def test_config_drift_blocked(self):
        self.production()
        self.cfg_path.write_text(self.cfg_path.read_text() + '\n')
        self.assertEqual(self.run_cli(demo=False), 1)

    def test_template_drift_blocked(self):
        path = self.project / 'dashboard_template/template.html'
        path.write_text(path.read_text() + '<p>changed</p>')
        self.assertEqual(self.run_cli(), 1)

    def test_older_promotion_blocked(self):
        self.production()
        self.assertEqual(self.run_cli(demo=False, promote=True), 0)
        self.data['manifest'].update(run_id='1792499999_2', observation_end=1792499999, attempt_id=2)
        self.assertEqual(self.run_cli(demo=False, promote=True), 1)

    def test_changed_existing_run_blocked(self):
        self.assertEqual(self.run_cli(), 0)
        self.data['cohort'][0]['sales'] = 100
        self.assertEqual(self.run_cli(), 1)

    def test_symlink_output_blocked(self):
        out = self.project / 'dashboard_output/runs'
        if out.exists():
            shutil.rmtree(out)
        out.symlink_to(Path(self.temp.name).resolve(), target_is_directory=True)
        self.assertEqual(self.run_cli(), 1)


if __name__ == '__main__':
    unittest.main()
