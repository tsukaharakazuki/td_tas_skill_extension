#!/usr/bin/env python3
"""Unit tests for scripts/check_sql.py. No engine, no network, no query execution.

Run from any trusted directory:
  python3 -I /path/to/td-sql-workflow-reference/tests/test_check_sql.py
"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

# Keep the shared clone free of __pycache__ output from loading the script.
sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.normpath(os.path.join(HERE, "..", "scripts", "check_sql.py"))

_spec = importlib.util.spec_from_file_location("check_sql_under_test", SCRIPT)
check_sql = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_sql)


def rules_for(text, engine="hive", mode="standalone"):
    return [f["rule"] for f in check_sql.check_text("t.sql", text, engine, mode)]


def markers_for(text, engine="trino"):
    return check_sql.find_markers(check_sql.tokenize(text, engine))


def run_cli(args, cwd):
    proc = subprocess.run(
        [sys.executable, "-I", SCRIPT] + args,
        cwd=cwd, capture_output=True, text=True)
    return proc.returncode, proc.stdout, proc.stderr


class LexicalTests(unittest.TestCase):

    def test_line_comment_hides_cast_varchar(self):
        text = "SELECT 1 -- CAST(x AS VARCHAR)\n"
        self.assertEqual(rules_for(text, "hive", "standalone"), [])

    def test_block_comment_hides_try_cast(self):
        text = "/* TRY_CAST(x AS INT) and ARRAY[1] */ SELECT 1"
        self.assertEqual(rules_for(text), [])

    def test_string_literal_hides_keywords(self):
        text = "SELECT 'CAST(x AS VARCHAR) || ARRAY[1] TRY(x)' AS s"
        self.assertEqual(rules_for(text), [])

    def test_doubled_quote_stays_inside_string(self):
        text = "SELECT 'it''s CAST(x AS VARCHAR)' AS s"
        self.assertEqual(rules_for(text), [])

    def test_quoted_identifier_is_not_keyword(self):
        text = 'SELECT "TRY_CAST" FROM t'
        self.assertEqual(rules_for(text), [])

    def test_case_is_not_cast(self):
        text = "SELECT CASE WHEN a THEN 1 ELSE 0 END AS flag FROM t"
        self.assertEqual(rules_for(text, "hive"), [])

    def test_token_line_numbers_follow_newlines(self):
        tokens = check_sql.tokenize("SELECT 1\n-- note\nTRY_CAST(x AS INT)")
        try_tok = [t for t in tokens if t.text == "TRY_CAST"][0]
        self.assertEqual(try_tok.line, 3)

    def test_unterminated_block_comment_does_not_crash(self):
        text = "SELECT 1 /* CAST(x AS VARCHAR)"
        self.assertEqual(rules_for(text, "hive"), [])

    def test_unquoted_japanese_identifiers_are_safe(self):
        self.assertEqual(rules_for("SELECT 顧客名, 金額 FROM 購買履歴"), [])

    def test_unicode_identifier_does_not_split_out_keywords(self):
        self.assertEqual(rules_for("SELECT 顧客CAST(x), TRY_CAST列, ARRAY列[1] FROM 表"), [])

    def test_fullwidth_and_other_unicode_digits_are_safe(self):
        self.assertEqual(rules_for("SELECT １２３, ², Ⅳ FROM 表"), [])

    def test_hive_backslash_escaped_quote_hides_fake_code(self):
        text = r"SELECT 'it\'s CAST(x AS VARCHAR) || TRY(x)' AS s"
        self.assertEqual(rules_for(text, "hive"), [])

    def test_hive_double_quoted_string_escaped_quote(self):
        text = r'SELECT "it\"s TRY(x) || ARRAY[1]" AS s'
        self.assertEqual(rules_for(text, "hive"), [])

    def test_hive_escaped_quote_does_not_expose_fake_marker(self):
        text = "SELECT 'it\\'s\n-- DIGDAG_INSERT_LINE\nTRY(x)'"
        self.assertEqual(markers_for(text, "hive"), [])
        self.assertEqual(rules_for(text, "hive"), [])

    def test_hive_string_keeps_backslashes_verbatim(self):
        text = r"SELECT 'it\'s \\. \d'"
        literal = [t for t in check_sql.tokenize(text, "hive") if t.kind == "string"][0]
        self.assertEqual(literal.text, text[len("SELECT "):])

    def test_trino_backslash_does_not_escape_quote(self):
        text = "SELECT '\\' AS s, TRY(x)"
        words = [t.text for t in check_sql.tokenize(text, "trino") if t.kind == "word"]
        self.assertIn("TRY", words)


class MarkerTests(unittest.TestCase):

    def test_active_line_comment_marker_detected(self):
        self.assertEqual(len(markers_for("-- DIGDAG_INSERT_LINE\nSELECT 1")), 1)

    def test_inline_marker_is_ignored(self):
        self.assertEqual(markers_for("SELECT 1 -- DIGDAG_INSERT_LINE"), [])

    def test_indented_marker_is_ignored(self):
        for prefix in (" ", "\t", "   "):
            self.assertEqual(markers_for(prefix + "-- DIGDAG_INSERT_LINE"), [])

    def test_marker_with_trailing_sql_is_ignored(self):
        self.assertEqual(markers_for("-- DIGDAG_INSERT_LINE SELECT 1"), [])

    def test_marker_allows_crlf_and_trailing_whitespace(self):
        self.assertEqual(len(markers_for("-- DIGDAG_INSERT_LINE \t\r\nSELECT 1")), 1)

    def test_multiple_active_markers_warn_in_all_modes(self):
        text = "-- DIGDAG_INSERT_LINE\n-- DIGDAG_INSERT_LINE\nSELECT 1"
        for engine in check_sql.ENGINES:
            for mode in check_sql.OUTPUT_MODES:
                self.assertIn("multiple-insert-markers", rules_for(text, engine, mode))

    def test_fake_markers_do_not_satisfy_hive_with(self):
        for fake in ("  -- DIGDAG_INSERT_LINE", "SELECT 1 -- DIGDAG_INSERT_LINE",
                     "/* -- DIGDAG_INSERT_LINE */", "SELECT '-- DIGDAG_INSERT_LINE'"):
            text = "WITH a AS (SELECT 1)\n" + fake
            self.assertIn("marker-missing-hive-with", rules_for(text, "hive", "insert-into"))

    def test_marker_inside_string_is_ignored(self):
        self.assertEqual(markers_for("SELECT '-- DIGDAG_INSERT_LINE' AS s"), [])

    def test_marker_inside_block_comment_is_ignored(self):
        text = "/*\n-- DIGDAG_INSERT_LINE\n*/\nSELECT 1"
        self.assertEqual(markers_for(text), [])

    def test_similar_marker_text_is_not_marker(self):
        self.assertEqual(markers_for("-- DIGDAG_INSERT_LINES\nSELECT 1"), [])
        self.assertEqual(markers_for("-- see DIGDAG_INSERT_LINE here\nSELECT 1"), [])

    def test_hive_with_without_marker_warns(self):
        text = "WITH a AS (SELECT 1 AS x)\nSELECT x FROM a"
        self.assertIn("marker-missing-hive-with", rules_for(text, "hive", "insert-into"))

    def test_hive_marker_before_with_warns(self):
        text = "-- DIGDAG_INSERT_LINE\nWITH a AS (SELECT 1 AS x)\nSELECT x FROM a"
        self.assertIn("marker-before-with-hive", rules_for(text, "hive", "create-table"))

    def test_hive_marker_after_with_is_clean(self):
        text = "WITH a AS (SELECT 1 AS x)\n-- DIGDAG_INSERT_LINE\nSELECT x FROM a"
        found = rules_for(text, "hive", "create-table")
        self.assertNotIn("marker-before-with-hive", found)
        self.assertNotIn("marker-missing-hive-with", found)

    def test_trino_marker_after_with_is_review(self):
        text = "WITH a AS (SELECT 1 AS x)\n-- DIGDAG_INSERT_LINE\nSELECT x FROM a"
        findings = check_sql.check_text("t.sql", text, "trino", "insert-into")
        marker = [f for f in findings if f["rule"] == "marker-after-with-trino"]
        self.assertEqual(len(marker), 1)
        self.assertEqual(marker[0]["severity"], "review")

    def test_trino_marker_before_with_is_not_flagged(self):
        text = "-- DIGDAG_INSERT_LINE\nWITH a AS (SELECT 1 AS x)\nSELECT x FROM a"
        found = rules_for(text, "trino", "create-table")
        self.assertFalse([r for r in found if r.startswith("marker-")])

    def test_standalone_mode_has_no_marker_findings(self):
        text = "WITH a AS (SELECT 1 AS x)\nSELECT x FROM a"
        self.assertFalse([r for r in rules_for(text, "hive", "standalone")
                          if r.startswith("marker-")])

    def test_with_table_property_is_not_cte(self):
        text = "CREATE TABLE t WITH (format = 'ORC') AS SELECT 1 AS x"
        self.assertFalse([r for r in rules_for(text, "hive", "create-table")
                          if r.startswith("marker-")])


class RuleTests(unittest.TestCase):

    def test_hive_cast_varchar_warns(self):
        findings = check_sql.check_text(
            "t.sql", "SELECT CAST(x AS VARCHAR(10)) FROM t", "hive", "standalone")
        self.assertIn("hive-cast-varchar", [f["rule"] for f in findings])

    def test_trino_cast_varchar_not_hive_warning(self):
        self.assertNotIn("hive-cast-varchar",
                         rules_for("SELECT CAST(x AS VARCHAR) FROM t", "trino"))

    def test_cast_int_is_advisory_not_warning(self):
        findings = check_sql.check_text(
            "t.sql", "SELECT CAST(x AS INT) FROM t", "trino", "standalone")
        narrow = [f for f in findings if f["rule"] == "cast-int-narrowing"]
        self.assertEqual(len(narrow), 1)
        self.assertEqual(narrow[0]["severity"], "advisory")

    def test_bigint_cast_not_flagged(self):
        self.assertEqual(rules_for("SELECT CAST(x AS BIGINT) FROM t", "hive"), [])

    def test_try_cast_warns(self):
        self.assertIn("try-cast", rules_for("SELECT TRY_CAST(x AS INT) FROM t"))

    def test_try_function_warns(self):
        self.assertIn("try-function", rules_for("SELECT TRY(url_extract_host(u)) FROM t"))

    def test_array_constructor_warns_but_array_call_does_not(self):
        self.assertIn("array-constructor", rules_for("SELECT ARRAY[1, 2] AS a"))
        self.assertNotIn("array-constructor", rules_for("SELECT array(1, 2) AS a"))

    def test_concat_operator_warns_and_concat_call_does_not(self):
        self.assertIn("concat-operator", rules_for("SELECT a || b FROM t"))
        self.assertNotIn("concat-operator", rules_for("SELECT CONCAT(a, b) FROM t"))

    def test_review_functions_are_review_severity(self):
        text = ("SELECT JSON_FORMAT(j), TO_UTF8(s), TO_HEX(b), REGEXP_LIKE(s, 'a')\n"
                "FROM t")
        findings = check_sql.check_text("t.sql", text, "hive", "standalone")
        review = [f for f in findings if f["severity"] == "review"]
        self.assertGreaterEqual(len(review), 4)

    def test_regex_single_backslash_before_metachar_is_review(self):
        text = "SELECT REGEXP_REPLACE(s, '\\.', '') FROM t"
        self.assertIn("regex-single-backslash", rules_for(text, "hive"))

    def test_regex_doubled_backslash_not_flagged(self):
        text = "SELECT REGEXP_REPLACE(s, '\\\\.', '') FROM t"
        self.assertNotIn("regex-single-backslash", rules_for(text, "hive"))

    def test_backslash_outside_regex_function_not_flagged(self):
        self.assertNotIn("regex-single-backslash", rules_for("SELECT '\\.' AS s", "hive"))

    def test_legitimate_trino_constructs_are_clean(self):
        text = (r"SELECT TRY_CAST(x AS BIGINT), TRY(x / y), ARRAY[1,2], a || b, "
                r"JSON_FORMAT(j), TO_UTF8(s), TO_HEX(b), REGEXP_LIKE(s, '\d+'), "
                r"REGEXP_REPLACE(s, '\.', '') FROM t")
        self.assertEqual(rules_for(text, "trino"), [])

    def test_int_advisory_has_no_universal_truncation_claim(self):
        for engine in check_sql.ENGINES:
            findings = check_sql.check_text("t.sql", "SELECT CAST(x AS INT)", engine, "standalone")
            self.assertEqual(findings[0]["severity"], "advisory")
            self.assertIn("rounding", findings[0]["message"])
            self.assertNotIn("truncates", findings[0]["message"])

    def test_try_cast_column_name_is_not_a_function(self):
        self.assertEqual(rules_for("SELECT try_cast FROM t"), [])

    def test_regex_function_first_input_literal_is_not_pattern(self):
        text = r"SELECT REGEXP_REPLACE('\d', 'plain', '')"
        self.assertNotIn("regex-single-backslash", rules_for(text))

    def test_regex_function_replacement_literal_is_not_pattern(self):
        text = r"SELECT REGEXP_REPLACE(s, 'plain', '\d')"
        self.assertNotIn("regex-single-backslash", rules_for(text))

    def test_regex_pattern_shorthands_warn_on_hive(self):
        for escape in (r"\d", r"\s", r"\w", r"\D", r"\S", r"\W", r"\."):
            text = "SELECT REGEXP_EXTRACT(s, '%s', 0)" % escape
            self.assertIn("regex-single-backslash", rules_for(text), escape)

    def test_regex_infix_rlike_pattern_is_inspected(self):
        self.assertIn("regex-single-backslash", rules_for(r"SELECT s RLIKE '\d+' FROM t"))

    def test_regex_infix_regexp_pattern_is_inspected(self):
        self.assertIn("regex-single-backslash", rules_for(r"SELECT s REGEXP '\w+' FROM t"))

    def test_regex_infix_input_literal_not_inspected(self):
        self.assertNotIn("regex-single-backslash", rules_for(r"SELECT '\d' RLIKE 'plain'"))

    def test_regex_nested_function_arguments_do_not_confuse_pattern(self):
        text = r"SELECT REGEXP_REPLACE(CONCAT('\d', ',x'), '\.', 'x')"
        findings = check_sql.check_text("t.sql", text, "hive", "standalone")
        self.assertEqual(len([f for f in findings if f["rule"] == "regex-single-backslash"]), 1)

    def test_regex_computed_pattern_not_inspected(self):
        text = r"SELECT REGEXP_REPLACE(s, CONCAT('\d', '$'), '')"
        self.assertNotIn("regex-single-backslash", rules_for(text))

    def test_regex_odd_and_even_backslash_runs(self):
        for count in (1, 2, 3, 4):
            text = "SELECT REGEXP_REPLACE(s, '" + "\\" * count + "d', '')"
            self.assertEqual("regex-single-backslash" in rules_for(text), count % 2 == 1)

    def test_correct_trino_single_slash_has_no_regex_warning(self):
        self.assertEqual(rules_for(r"SELECT REGEXP_EXTRACT(s, '\d+', 0)", "trino"), [])


class FileAndCliTests(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = self._tmp.name

    def tearDown(self):
        self._tmp.cleanup()

    def write(self, name, data):
        path = os.path.join(self.dir, name)
        mode = "wb" if isinstance(data, bytes) else "w"
        with open(path, mode) as fh:
            fh.write(data)
        return path

    def test_output_mode_defaults_to_standalone(self):
        path = self.write("cte.sql", "WITH a AS (SELECT 1) SELECT * FROM a")
        code, out, _ = run_cli(["--engine", "hive", "--json", path], self.dir)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["output_mode"], "standalone")

    def test_legitimate_trino_file_is_clean_json(self):
        path = self.write("trino.sql", r"SELECT TRY_CAST(x AS BIGINT), ARRAY[1], s || s, REGEXP_LIKE(s, '\d+')")
        code, out, _ = run_cli(["--engine", "trino", "--json", path], self.dir)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["findings"], [])

    def test_unicode_sql_file_is_safe_on_cli(self):
        path = self.write("unicode.sql", "SELECT 顧客名, １２３ FROM 購買履歴")
        code, out, _ = run_cli(["--engine", "hive", "--json", path], self.dir)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["files_checked"], [path])

    def test_clean_file_exits_zero(self):
        path = self.write("clean.sql", "SELECT 1 AS x\n")
        code, out, _ = run_cli(["--engine", "hive", "--output-mode", "standalone", path], self.dir)
        self.assertEqual(code, 0)
        self.assertIn("files checked: 1", out)

    def test_findings_exit_one(self):
        path = self.write("warn.sql", "SELECT TRY_CAST(x AS INT) FROM t\n")
        code, _, _ = run_cli(["--engine", "hive", "--output-mode", "standalone", path], self.dir)
        self.assertEqual(code, 1)

    def test_missing_file_exits_two(self):
        missing = os.path.join(self.dir, "absent.sql")
        code, _, err = run_cli(["--engine", "hive", "--output-mode", "standalone", missing], self.dir)
        self.assertEqual(code, 2)
        self.assertIn("file not found", err)

    def test_directory_path_exits_two(self):
        code, _, err = run_cli(["--engine", "hive", "--output-mode", "standalone", self.dir], self.dir)
        self.assertEqual(code, 2)
        self.assertIn("directory", err)

    def test_non_utf8_file_exits_two(self):
        path = self.write("bad.sql", b"\xff\xfeSELECT 1")
        code, _, err = run_cli(["--engine", "hive", "--output-mode", "standalone", path], self.dir)
        self.assertEqual(code, 2)
        self.assertIn("UTF-8", err)

    def test_bad_engine_argument_exits_two(self):
        path = self.write("ok.sql", "SELECT 1\n")
        code, _, _ = run_cli(["--engine", "spark", "--output-mode", "standalone", path], self.dir)
        self.assertEqual(code, 2)

    def test_bad_output_mode_argument_exits_two(self):
        path = self.write("ok.sql", "SELECT 1\n")
        code, _, _ = run_cli(["--engine", "hive", "--output-mode", "bogus", path], self.dir)
        self.assertEqual(code, 2)

    def test_each_output_mode_is_accepted(self):
        path = self.write("ok.sql", "SELECT 1\n")
        for mode in check_sql.OUTPUT_MODES:
            code, _, _ = run_cli(["--engine", "trino", "--output-mode", mode, path], self.dir)
            self.assertEqual(code, 0, mode)

    def test_json_report_schema_and_findings(self):
        path = self.write("warn.sql",
                          "-- DIGDAG_INSERT_LINE\nWITH a AS (SELECT CAST(x AS VARCHAR) AS s FROM t)\n"
                          "SELECT s FROM a\n")
        code, out, _ = run_cli(
            ["--engine", "hive", "--output-mode", "insert-into", "--json", path], self.dir)
        self.assertEqual(code, 1)
        report = json.loads(out)
        self.assertEqual(report["engine"], "hive")
        self.assertEqual(report["output_mode"], "insert-into")
        self.assertEqual(report["files_checked"], [path])
        self.assertEqual(report["file_errors"], [])
        self.assertEqual(report["status"], "warnings")
        self.assertIn("Heuristic", report["disclaimer"])
        self.assertIn("not a runtime", report["disclaimer"])
        self.assertTrue(report["findings"])
        for finding in report["findings"]:
            for key in ("rule", "severity", "path", "line", "code", "message"):
                self.assertIn(key, finding)

    def test_json_clean_run_reports_no_findings(self):
        path = self.write("clean.sql", "SELECT 1 AS x\n")
        code, out, _ = run_cli(
            ["--engine", "trino", "--output-mode", "create-table", "--json", path], self.dir)
        self.assertEqual(code, 0)
        report = json.loads(out)
        self.assertEqual(report["status"], "no_findings")
        self.assertEqual(report["findings"], [])

    def test_json_file_error_reports_and_exits_two(self):
        good = self.write("good.sql", "SELECT 1\n")
        missing = os.path.join(self.dir, "gone.sql")
        code, out, _ = run_cli(
            ["--engine", "hive", "--output-mode", "standalone", "--json", good, missing], self.dir)
        self.assertEqual(code, 2)
        report = json.loads(out)
        self.assertEqual(report["status"], "error")
        self.assertEqual(report["files_checked"], [good])
        self.assertEqual(report["file_errors"][0]["path"], missing)

    def test_multiple_files_are_each_reported(self):
        a = self.write("a.sql", "SELECT TRY_CAST(x AS INT) FROM t\n")
        b = self.write("b.sql", "SELECT 1\n")
        code, out, _ = run_cli(
            ["--engine", "hive", "--output-mode", "standalone", "--json", a, b], self.dir)
        self.assertEqual(code, 1)
        report = json.loads(out)
        self.assertEqual(report["files_checked"], [a, b])
        self.assertEqual({f["path"] for f in report["findings"]}, {a})


if __name__ == "__main__":
    unittest.main()
