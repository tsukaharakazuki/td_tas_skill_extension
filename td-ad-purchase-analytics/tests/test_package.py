"""Check the shipped package structure. This is not a TD execution test."""
import hashlib
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'templates/project'


class PackageTests(unittest.TestCase):
    def test_skill_frontmatter_and_size(self):
        text = (ROOT / 'SKILL.md').read_text()
        self.assertTrue(text.startswith('---\nname: td-ad-purchase-analytics\n'))
        header = text.split('---', 2)[1]
        description = next(line for line in header.splitlines() if line.startswith('description: '))
        self.assertIn('広告獲得分析', description)
        self.assertNotIn(': ', description[len('description: '):])
        self.assertLessEqual(len(text.splitlines()), 200)

    def test_workflow_sql_paths_exist(self):
        workflow = (PROJECT / 'ad_purchase_analytics.dig').read_text()
        paths = re.findall(r'td>:\s*(queries/[^\s]+\.sql)', workflow)
        self.assertGreaterEqual(len(paths), 15)
        for path in paths:
            with self.subTest(path=path):
                self.assertTrue((PROJECT / path).is_file())

    def test_all_referenced_marts_are_built(self):
        workflow = (PROJECT / 'ad_purchase_analytics.dig').read_text()
        built = set(re.findall(r'create_table: \$\{table_prefix\}_([a-z_]+)_\$\{session_unixtime\}', workflow))
        self.assertIn('complete', built)
        for path in (PROJECT / 'queries').glob('*.sql'):
            referenced = re.findall(r'\$\{table_prefix\}_([a-z_]+)_\$\{session_unixtime\}', path.read_text())
            for mart in referenced:
                with self.subTest(path=path.name, mart=mart):
                    self.assertIn(mart, built)

    def test_default_has_no_schedule_or_activation(self):
        text = (PROJECT / 'ad_purchase_analytics.dig').read_text()
        self.assertNotRegex(text, r'(?m)^schedule:')
        self.assertNotRegex(text, r'(?m)^\s*(mail|http|td_export|td_result_export|td_table_export)>:')
        cfg = json.loads((PROJECT / 'config/project.json').read_text())
        self.assertIs(cfg['configured'], False)
        self.assertIs(cfg['ad_costs_enabled'], False)
        self.assertIn('if>: ${!configuration_reviewed}', text)
        self.assertIn('if>: ${td.last_results.hard_errors > 0}', text)
        self.assertLess(text.index('+assert_qa:'), text.index('+complete:'))

    def test_template_pin(self):
        cfg = json.loads((PROJECT / 'config/project.json').read_text())
        digest = hashlib.sha256((PROJECT / 'dashboard_template/template.html').read_bytes()).hexdigest()
        self.assertEqual(digest, cfg['dashboard_template']['sha256'])
        self.assertRegex(cfg['dashboard_template']['commit'], r'^[a-f0-9]{40}$')
        text = (PROJECT / 'dashboard_template/template.html').read_text()
        self.assertIn('tas-logo-horizontal', text)
        self.assertIn('Prepared by Treasure Data', text)

    def test_upload_exclusions(self):
        text = (PROJECT / '.digdagignore').read_text()
        for path in ('runs/', 'dashboard_output/', 'dashboard_template/', 'MEMORY.md', 'config/project.json'):
            self.assertIn(path, text)

    def test_project_ignore_does_not_hide_bundled_templates(self):
        patterns = (ROOT / '.gitignore').read_text().splitlines()
        self.assertIn('/Project/', patterns)
        self.assertNotIn('Project/', patterns)

    def test_local_markdown_reference_links(self):
        for path in [ROOT / 'SKILL.md', *list((ROOT / 'references').glob('*.md'))]:
            for link in re.findall(r'\]\(([^)]+)\)', path.read_text()):
                if '://' not in link and not link.startswith('#') and '<' not in link:
                    with self.subTest(path=path.name, link=link):
                        self.assertTrue((path.parent / link.split('#', 1)[0]).exists())


if __name__ == '__main__':
    unittest.main()
