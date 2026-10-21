"""Offline CLI regression tests; no installed skill, TD account or YAML library needed.

Run: python3 -I -m unittest discover -s /absolute/skill/tests -v
"""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PACKAGE = Path(__file__).resolve().parents[1]
INIT = PACKAGE / "scripts" / "init_project.py"
VALIDATE = PACKAGE / "scripts" / "validate_project.py"


def valid_config():
    return {
        "configured": True,
        "project_name": "demo_store",
        "output_database": "analytics",
        "table_prefix": "ads",
        "web_table": "source.web_events",
        "purchase_mode": "web",
        "session_mode": "window",
        "session_timeout_seconds": 1800,
        "lookback_days": 30,
        "report_start": "2026-09-01",
        "report_end": "2026-10-01",
        "timezone": "Asia/Tokyo",
        "currency": "JPY",
        "internal_hosts": ["example.com", "www.example.com"],
        "ad_costs_enabled": False,
        "refresh_strategy": "full_retained_history",
        "dashboard_template": {
            "repository": "https://github.com/example/dashboard",
            "commit": "7d087a31a2625341a6d5811d149fd633859bda32",
            "sha256": "f6f72d7512ea389d03ec09a31f7d1e034f6737395b7a81ebf4c4cabdc0111ef2",
        },
    }


def write_file(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def write_json(path, content):
    write_file(path, json.dumps(content, indent=2) + "\n")


def populate_project(project):
    write_json(project / "config/project.json", valid_config())
    write_file(project / "config/params.yml", "configuration_reviewed: true\n")
    write_json(project / "tdx.json", {"database": "analytics", "workflow_project": "demo_store"})
    write_file(project / "ad_purchase_analytics.dig", "_export:\n  !include : config/params.yml\n")
    write_json(project / "dashboard_output/mapping.json", {"tables": {}})
    write_file(project / "queries/00_web.sql", "SELECT 1 AS example\n")
    write_file(project / "queries/00_orders_separate.sql", "SELECT 1 AS example\n")
    write_file(project / "queries/00_costs.sql", "SELECT 1 AS example\n")
    write_file(project / "MEMORY.md", "# Project memory\n")
    write_file(project / "README.md", "Fixture project.\n")


class ToolTestCase(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ad-purchase-tools-")
        # macOS's /var and /tmp may be symlinks; test actual filesystem paths.
        self.root = Path(self.temporary.name).resolve()
        self.addCleanup(self.temporary.cleanup)

    def run_cli(self, script, *arguments, cwd=None):
        return subprocess.run([sys.executable, "-I", str(script), *(str(arg) for arg in arguments)],
                              cwd=str(cwd or self.root), capture_output=True, text=True,
                              timeout=15, check=False)

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_failure(self, result, text=None):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        if text:
            self.assertIn(text, result.stderr)


class InitializeTests(ToolTestCase):
    def setUp(self):
        super().setUp()
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.skill = self.root / "fake-skill"
        self.script = self.skill / "scripts/init_project.py"
        self.script.parent.mkdir(parents=True)
        shutil.copyfile(INIT, self.script)
        self.template = self.skill / "templates/project"
        populate_project(self.template)
        self.project = self.workspace / "Project/demo_store"

    def initialize(self, *extra, name="demo_store", workspace=None):
        return self.run_cli(self.script, "--workspace", workspace or self.workspace,
                            "--name", name, *extra)

    def test_creates_singular_project_and_prints_paths(self):
        result = self.initialize()
        self.assert_success(result)
        self.assertFalse((self.workspace / "Projects").exists())
        self.assertEqual((self.project / "MEMORY.md").read_text(), "# Project memory\n")
        for name in ("dashboard_output", "dashboard_template", "runs"):
            self.assertTrue((self.project / name).is_dir())
        self.assertIn(str(self.project / "README.md"), result.stdout)
        self.assertEqual((self.workspace / "Project/MEMORY.md").read_text(),
                         "- [demo_store](demo_store/MEMORY.md)\n")

    def test_preserves_existing_index_and_appends_once(self):
        index = self.workspace / "Project/MEMORY.md"
        original = "# Existing projects\n- [other](other/MEMORY.md)"
        write_file(index, original)
        self.assert_success(self.initialize())
        self.assertEqual(index.read_text(), original + "\n- [demo_store](demo_store/MEMORY.md)\n")
        before = index.read_bytes()
        self.assert_failure(self.initialize(), "already exists")
        self.assertEqual(index.read_bytes(), before)

    def test_does_not_duplicate_existing_pointer(self):
        index = self.workspace / "Project/MEMORY.md"
        original = "# Retained\n- [Existing label](./demo_store/MEMORY.md)\n"
        write_file(index, original)
        self.assert_success(self.initialize())
        self.assertEqual(index.read_text(), original)

    def test_existing_project_is_not_touched(self):
        write_file(self.project / "keep.txt", "do not change")
        self.assert_failure(self.initialize(), "already exists")
        self.assertEqual((self.project / "keep.txt").read_text(), "do not change")
        self.assertFalse((self.project / "config").exists())

    def test_rejects_traversal_and_nonascii_slugs(self):
        for name in ("../escape", "a/b", "/absolute", ".", "..", "has space", "店舗", "Upper", "x" * 65):
            with self.subTest(name=name):
                self.assert_failure(self.initialize(name=name), "ASCII slug")
        self.assertFalse((self.workspace / "Project").exists())

    def test_dry_run_does_not_create_project_or_index(self):
        result = self.initialize("--dry-run")
        self.assert_success(result)
        self.assertIn("Dry run", result.stdout)
        self.assertIn(str(self.project), result.stdout)
        self.assertFalse((self.workspace / "Project").exists())

    def test_dry_run_does_not_modify_existing_index(self):
        index = self.workspace / "Project/MEMORY.md"
        write_file(index, "existing index with no newline")
        before = index.read_bytes()
        self.assert_success(self.initialize("--dry-run"))
        self.assertEqual(index.read_bytes(), before)
        self.assertFalse(self.project.exists())

    def test_excludes_git_environments_and_secret_files(self):
        excluded = (".git/config", ".env", ".env.local", ".envrc", "env/bin/python", ".venv/config",
                    "secrets/password.txt", "secrets.toml", "credentials.json", ".tdx/config.json",
                    "server.key", "private.pem")
        for name in excluded:
            write_file(self.template / name, "DO NOT COPY")
        self.assert_success(self.initialize())
        for name in excluded:
            self.assertFalse((self.project / name).exists(), name)
        self.assertTrue((self.project / "config/project.json").exists())

    def test_rejects_template_file_and_directory_symlinks(self):
        outside = self.root / "outside"
        outside.mkdir()
        write_file(outside / "secret", "keep")
        for name, target in (("linked-file", outside / "secret"), ("linked-dir", outside)):
            with self.subTest(name=name):
                link = self.template / name
                link.symlink_to(target)
                self.assert_failure(self.initialize(), "symlink")
                self.assertFalse((self.workspace / "Project").exists())
                link.unlink()

    def test_rejects_workspace_project_root_index_and_destination_symlinks(self):
        external = self.root / "external"
        external.mkdir()
        workspace_link = self.root / "workspace-link"
        workspace_link.symlink_to(self.workspace)
        self.assert_failure(self.initialize(workspace=workspace_link), "symlink")
        root_link = self.workspace / "Project"
        root_link.symlink_to(external)
        self.assert_failure(self.initialize(), "symlink")
        root_link.unlink()
        root_link.mkdir()
        write_file(external / "index", "keep")
        (root_link / "MEMORY.md").symlink_to(external / "index")
        self.assert_failure(self.initialize(), "symlink")
        self.assertEqual((external / "index").read_text(), "keep")
        (root_link / "MEMORY.md").unlink()
        self.project.symlink_to(external / "missing")
        self.assert_failure(self.initialize(), "symlink")

    def test_requires_template_memory_before_writing(self):
        (self.template / "MEMORY.md").unlink()
        self.assert_failure(self.initialize(), "MEMORY.md")
        self.assertFalse((self.workspace / "Project").exists())

    def test_workspace_must_exist_and_be_absolute(self):
        self.assert_failure(self.initialize(workspace=self.root / "missing"), "existing directory")
        self.assert_failure(self.initialize(workspace="workspace"), "absolute")


class ValidationTests(ToolTestCase):
    def setUp(self):
        super().setUp()
        self.project = self.root / "Project/demo_store"
        populate_project(self.project)
        self.config_path = self.project / "config/project.json"

    def validate(self, *extra, cwd=None):
        return self.run_cli(VALIDATE, self.project, *extra, cwd=cwd)

    def configure(self, **updates):
        config = json.loads(self.config_path.read_text())
        config.update(updates)
        write_json(self.config_path, config)
        return config

    def test_valid_project_succeeds_without_modifying_files(self):
        before = {path: path.read_bytes() for path in self.project.rglob("*") if path.is_file()}
        self.assert_success(self.validate())
        self.assertEqual({path: path.read_bytes() for path in before}, before)

    def test_extra_mapping_and_qa_fields_are_allowed(self):
        self.configure(qa={"minimum_sessions": 20, "required_columns": ["session_id", "order_id"]},
                       adapters={"web": {"identity_column": "td_client_id"}})
        self.assert_success(self.validate())

    def test_configuration_requires_explicit_boolean_review(self):
        for value in (False, "true", 1, None):
            with self.subTest(value=value):
                self.configure(configured=value)
                self.assert_failure(self.validate("--compile-config"), "configured")

    def test_dates_are_strict_iso_and_in_order(self):
        for updates in ({"report_start": "2026-02-30"}, {"report_start": "20260901"},
                        {"report_end": "2026-09-01"}, {"report_end": "2026-08-01"},
                        {"report_start": "2026-09-01T00:00:00"}):
            with self.subTest(updates=updates):
                write_json(self.config_path, valid_config())
                self.configure(**updates)
                self.assert_failure(self.validate(), "report_")

    def test_positive_counts_reject_booleans_floats_and_zero(self):
        for field in ("session_timeout_seconds", "lookback_days"):
            for value in (0, -1, True, 1.5, "30"):
                with self.subTest(field=field, value=value):
                    write_json(self.config_path, valid_config())
                    self.configure(**{field: value})
                    self.assert_failure(self.validate(), field)

    def test_modes_timezone_currency_and_refresh_strategy(self):
        for field, value in (("purchase_mode", "automatic"), ("session_mode", "guess"),
                             ("timezone", "Mars/Somewhere"), ("timezone", "../UTC"),
                             ("currency", "jpy"), ("currency", "JPY,USD"),
                             ("currency", ["JPY", "USD"]), ("ad_costs_enabled", "false"),
                             ("refresh_strategy", "incremental")):
            with self.subTest(field=field, value=value):
                write_json(self.config_path, valid_config())
                self.configure(**{field: value})
                self.assert_failure(self.validate(), field)
        self.configure(refresh_strategy="full_retained_history", purchase_mode="web", session_mode="sdk",
                       timezone="UTC", currency="USD", ad_costs_enabled=True)
        self.assert_success(self.validate())

    def test_sql_identifiers_and_prefix_length_are_checked(self):
        for field, value in (("output_database", "analytics; DROP TABLE x"),
                             ("output_database", "db-name"), ("table_prefix", "x" * 21),
                             ("table_prefix", ""), ("table_prefix", "ads.${other}"),
                             ("web_table", "catalog.db.table"), ("web_table", "db.t where 1=1"),
                             ("web_table", "db.table;"), ("project_name", "../escape")):
            with self.subTest(field=field, value=value):
                write_json(self.config_path, valid_config())
                self.configure(**{field: value})
                self.assert_failure(self.validate(), field)

    def test_hostnames_reject_blank_url_wildcard_and_sql(self):
        for hosts in ([], [""], [" "], "example.com", [None], ["https://example.com"],
                      ["example.com:443"], ["*.example.com"], ["bad_host.example"],
                      ["example.com' OR 1=1 --"], ["-bad.example"], ["example.com."],
                      ["例.example"], ["x" * 64 + ".example"]):
            with self.subTest(hosts=hosts):
                self.configure(internal_hosts=hosts)
                self.assert_failure(self.validate("--compile-config"), "internal_hosts")

    def test_dashboard_template_requires_pinned_commit_and_hash(self):
        for field, value in (("commit", None), ("commit", "main"), ("commit", "g" * 40),
                             ("commit", "a" * 39), ("sha256", None), ("sha256", "a" * 63),
                             ("repository", "REPLACE_ME"), ("repository", "")):
            with self.subTest(field=field, value=value):
                config = valid_config()
                config["dashboard_template"][field] = value
                write_json(self.config_path, config)
                self.assert_failure(self.validate(), "dashboard_template." + field)

    def test_false_configuration_cannot_compile_even_with_unpinned_template(self):
        config = valid_config()
        config["configured"] = False
        config["dashboard_template"].update(commit=None, sha256=None)
        write_json(self.config_path, config)
        before = (self.project / "config/params.yml").read_bytes()
        self.assert_failure(self.validate("--compile-config"), "configured is false")
        self.assertEqual((self.project / "config/params.yml").read_bytes(), before)

    def test_required_files_are_checked(self):
        for relative in ("config/params.yml", "tdx.json", "ad_purchase_analytics.dig",
                         "dashboard_output/mapping.json", "queries/00_web.sql"):
            with self.subTest(relative=relative):
                path = self.project / relative
                before = path.read_bytes()
                path.unlink()
                self.assert_failure(self.validate(), relative)
                path.write_bytes(before)

    def test_active_template_placeholders_are_rejected(self):
        for relative in ("ad_purchase_analytics.dig", "config/params.yml", "config/extra.yaml",
                         "queries/10_other.sql"):
            for token in ("REPLACE_ME", "@@source@@"):
                with self.subTest(relative=relative, token=token):
                    path = self.project / relative
                    before = path.read_bytes() if path.exists() else None
                    write_file(path, "SELECT '" + token + "'\n")
                    self.assert_failure(self.validate(), relative)
                    if before is None:
                        path.unlink()
                    else:
                        path.write_bytes(before)

    def test_adapter_todo_and_replace_tokens_are_rejected(self):
        for token in ("TODO", "TODO_SOURCE", "REPLACE", "REPLACE_SOURCE"):
            with self.subTest(token=token):
                write_file(self.project / "queries/00_web.sql", "SELECT " + token + "\n")
                self.assert_failure(self.validate(), "adapter token")

    def test_unused_separate_adapter_can_stay_unresolved_in_web_mode(self):
        write_file(self.project / "queries/00_orders_separate.sql", "SELECT REPLACE_ME FROM @@orders@@ -- TODO\n")
        self.assert_success(self.validate())
        self.configure(purchase_mode="separate")
        self.assert_failure(self.validate(), "00_orders_separate.sql")
        (self.project / "queries/00_orders_separate.sql").unlink()
        self.assert_failure(self.validate(), "missing configured SQL adapter")

    def test_separate_mode_with_both_adapters_succeeds(self):
        self.configure(purchase_mode="separate")
        self.assert_success(self.validate("--compile-config"))
        self.assertIn('purchase_mode: "separate"', (self.project / "config/params.yml").read_text())

    def test_sql_comments_and_reference_documents_are_not_placeholders(self):
        write_file(self.project / "queries/00_web.sql",
                   "-- TODO REPLACE_ME @@source@@\n/* REPLACE -- @@\n /* nested TODO */ */\n"
                   "SELECT '--not a comment' AS value -- REPLACE_ME\n")
        write_file(self.project / "queries/00_costs.sql",
                   "-- REPLACE_ME with optional cost mapping\nSELECT CAST(NULL AS DOUBLE) AS cost WHERE false\n")
        write_file(self.project / "references/example.sql", "SELECT REPLACE_ME\n")
        write_file(self.project / "README.md", "TODO replace REPLACE_ME and @@ placeholders.\n")
        self.assert_success(self.validate())

    def test_sql_quoted_strings_keep_active_placeholders(self):
        for sql in ("SELECT '@@source@@' -- comment\n", "SELECT 'it''s REPLACE_ME'\n",
                    'SELECT "REPLACE_ME" FROM source.table\n'):
            with self.subTest(sql=sql):
                write_file(self.project / "queries/00_web.sql", sql)
                self.assert_failure(self.validate(), "00_web.sql")

    def test_compile_config_generates_flat_json_scalar_yaml_and_neutral_tdx(self):
        self.configure(ad_costs_enabled=True, internal_hosts=["Example.COM", "www.example.com"])
        write_file(self.project / "config/params.yml", "database: REPLACE_ME\nsource: @@source@@\n")
        write_json(self.project / "tdx.json", {"database": "REPLACE_ME", "workflow_project": "REPLACE_ME"})
        self.assert_failure(self.validate(), "params.yml")
        self.assert_success(self.validate("--compile-config"))
        params = (self.project / "config/params.yml").read_text()
        expected = {
            "configuration_reviewed": True,
            "config_sha256": hashlib.sha256(self.config_path.read_bytes()).hexdigest(),
            "table_prefix": "ads", "web_table": "source.web_events",
            "purchase_mode": "web", "session_mode": "window", "session_timeout_seconds": 1800,
            "lookback_days": 30, "report_start": "2026-09-01", "report_end": "2026-10-01",
            "report_timezone": "Asia/Tokyo", "currency": "JPY", "ad_costs_enabled": True,
            "refresh_strategy": "full_retained_history",
            "internal_hosts_sql": "('example.com','www.example.com')",
        }
        parsed = {}
        for line in params.splitlines():
            if not line or line.startswith(("#", " ")) or line == "td:":
                continue
            key, scalar = line.split(": ", 1)
            parsed[key] = json.loads(scalar)
        self.assertEqual(parsed, expected)
        self.assertIn('  database: "analytics"\n  engine: "presto"\n', params)
        self.assertNotIn("run_key", params)
        self.assertEqual(json.loads((self.project / "tdx.json").read_text()),
                         {"database": "analytics", "workflow_project": "demo_store"})
        self.assert_success(self.validate())
        before = params
        self.assert_success(self.validate("--compile-config"))
        self.assertEqual((self.project / "config/params.yml").read_text(), before)

    def test_compiled_hash_tracks_exact_project_json_bytes(self):
        self.assert_success(self.validate("--compile-config"))
        params_path = self.project / "config/params.yml"
        first_digest = hashlib.sha256(self.config_path.read_bytes()).hexdigest()
        self.assertIn('config_sha256: "' + first_digest + '"', params_path.read_text())
        self.config_path.write_bytes(self.config_path.read_bytes() + b"\n")
        self.assert_success(self.validate("--compile-config"))
        second_digest = hashlib.sha256(self.config_path.read_bytes()).hexdigest()
        self.assertNotEqual(first_digest, second_digest)
        self.assertIn('config_sha256: "' + second_digest + '"', params_path.read_text())

    def test_compile_can_create_missing_generated_files(self):
        for relative in ("config/params.yml", "tdx.json"):
            (self.project / relative).unlink()
        self.assert_success(self.validate("--compile-config"))
        self.assert_success(self.validate())

    def test_compile_does_not_write_on_invalid_schema_or_other_placeholders(self):
        for bad_field, value in (("output_database", "db;sql"), ("output_database", "REPLACE_ME"),
                                 ("web_table", "REPLACE_ME.events"), ("internal_hosts", ["x'bad"])):
            with self.subTest(field=bad_field):
                write_json(self.config_path, valid_config())
                self.configure(**{bad_field: value})
                params = self.project / "config/params.yml"
                tdx = self.project / "tdx.json"
                before = (params.read_bytes(), tdx.read_bytes())
                self.assert_failure(self.validate("--compile-config"), bad_field)
                self.assertEqual((params.read_bytes(), tdx.read_bytes()), before)
        write_json(self.config_path, valid_config())
        write_file(self.project / "queries/10_other.sql", "SELECT REPLACE_ME\n")
        before = (self.project / "config/params.yml").read_bytes()
        self.assert_failure(self.validate("--compile-config"), "10_other.sql")
        self.assertEqual((self.project / "config/params.yml").read_bytes(), before)

    def test_forbidden_secret_keys_are_rejected_recursively(self):
        for key in ("api_key", "apiKey", "TD_API_KEY", "password", "access_token", "private_key", "credentials"):
            with self.subTest(key=key):
                self.configure(extension={"items": [{key: "not-an-actual-secret"}]})
                self.assert_failure(self.validate(), key)

    def test_tdx_forbids_profile_site_and_api_keys_including_compile(self):
        for key in ("profile", "profiles", "site", "td_site", "api_key", "apiKey", "td_api_key"):
            with self.subTest(key=key):
                path = self.project / "tdx.json"
                write_json(path, {"database": "analytics", "extension": {key: "blocked"}})
                before = path.read_bytes()
                self.assert_failure(self.validate(), key)
                self.assert_failure(self.validate("--compile-config"), key)
                self.assertEqual(path.read_bytes(), before)

    def test_rejects_file_and_directory_symlinks_anywhere(self):
        outside = self.root / "external"
        outside.mkdir()
        write_file(outside / "untouched", "keep")
        for target in (outside, outside / "untouched", outside / "missing"):
            with self.subTest(target=target):
                link = self.project / "unexpected-link"
                link.symlink_to(target)
                self.assert_failure(self.validate("--compile-config"), "symlink")
                self.assertEqual((outside / "untouched").read_text(), "keep")
                link.unlink()

    def test_compile_refuses_symlink_destination(self):
        external = self.root / "external.yml"
        write_file(external, "unchanged\n")
        destination = self.project / "config/params.yml"
        destination.unlink()
        destination.symlink_to(external)
        self.assert_failure(self.validate("--compile-config"), "symlink")
        self.assertEqual(external.read_text(), "unchanged\n")

    def test_absolute_project_path_required_and_linked_project_rejected(self):
        self.assert_failure(self.run_cli(VALIDATE, "Project/demo_store"), "absolute")
        link = self.root / "linked-project"
        link.symlink_to(self.project)
        self.assert_failure(self.run_cli(VALIDATE, link), "symlink")
        self.assert_failure(self.run_cli(VALIDATE, self.project / ".." / "demo_store"), "must not contain")

    def test_invalid_json_and_duplicate_keys_are_errors_not_tracebacks(self):
        for text in ("[]", "{", '{"configured": true, "configured": false}', '{"configured": NaN}'):
            with self.subTest(text=text):
                write_file(self.config_path, text)
                self.assert_failure(self.validate(), "config/project.json")
        write_json(self.config_path, valid_config())
        write_file(self.project / "tdx.json", "[]")
        self.assert_failure(self.validate(), "tdx.json")

    def test_isolated_cli_does_not_import_project_modules(self):
        write_file(self.project / "json.py", "raise RuntimeError('project module must never be imported')\n")
        write_file(self.project / "zoneinfo.py", "raise RuntimeError('project module must never be imported')\n")
        self.assert_success(self.validate(cwd=self.project))


if __name__ == "__main__":
    unittest.main()
