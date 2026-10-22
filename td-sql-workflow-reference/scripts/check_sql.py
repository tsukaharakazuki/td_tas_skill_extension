#!/usr/bin/env python3
"""Read-only, offline, heuristic SQL migration risk checker (stdlib only).

This is a HEURISTIC lexical scanner. It is not a full SQL parser, not a
Digdag/Workflow validator, and not a runtime or semantic-equivalence check.
A clean run does NOT mean the SQL runs successfully on Hive or Trino.

Usage:
  python3 -I scripts/check_sql.py --engine hive|trino \
      [--output-mode standalone|create-table|insert-into] FILE [FILE ...] [--json]

Exit codes:
  0  no heuristic findings
  1  one or more warnings (review findings)
  2  file or argument failure
"""

import argparse
import json
import os
import re
import sys

ENGINES = ("hive", "trino")
OUTPUT_MODES = ("standalone", "create-table", "insert-into")
MARKER = "DIGDAG_INSERT_LINE"

EXIT_OK = 0
EXIT_WARN = 1
EXIT_FAIL = 2

DISCLAIMER = (
    "Heuristic lexical check only. Not a full SQL parser, not Digdag/Workflow "
    "validation, not a runtime or semantic-equivalence check. No finding means "
    "no heuristic matched; it does not mean the SQL runs successfully."
)

# Severity levels: "warning" = likely needs change; "review" = may need a look.
SEV_WARNING = "warning"
SEV_REVIEW = "review"
SEV_ADVISORY = "advisory"


# ---------------------------------------------------------------------------
# Lexer: splits SQL text into code / comment / string / marker spans so rules
# only fire on real code tokens.
# ---------------------------------------------------------------------------

class Token(object):
    __slots__ = ("kind", "text", "line", "col", "start", "end")

    def __init__(self, kind, text, line, col, start, end):
        self.kind = kind      # "word", "symbol", "string", "comment", "number", "ws"
        self.text = text
        self.line = line      # 1-based
        self.col = col        # 1-based
        self.start = start
        self.end = end

    def __repr__(self):
        return "Token(%s,%r,%d)" % (self.kind, self.text, self.line)


_WORD_RE = re.compile(r"\w+")
_NUM_RE = re.compile(r"[0-9]+(?:\.[0-9]*)?(?:[eE][+-]?[0-9]+)?")


def tokenize(text, engine="trino"):
    """Return tokens without decoding or changing literal backslashes.

    Handles non-nested comments, doubled quote escapes and Unicode words. Hive
    single/double-quoted strings also honour backslash-escaped characters when
    finding the closing quote; Trino strings use doubled quotes only. Double
    quotes are identifiers on Trino, strings on Hive; backticks are identifiers.
    This models common literal syntax, not every engine/version/session setting.
    """
    tokens = []
    i = 0
    n = len(text)

    def add(kind, start, end):
        tokens.append(Token(kind, text[start:end], line_at(start),
                            start - line_start_at(start) + 1, start, end))

    # Precompute line starts for accurate line/col lookups.
    line_starts = [0]
    for idx, ch in enumerate(text):
        if ch == "\n":
            line_starts.append(idx + 1)

    def line_at(pos):
        lo, hi = 0, len(line_starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if line_starts[mid] <= pos:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1

    def line_start_at(pos):
        return line_starts[line_at(pos) - 1]

    while i < n:
        ch = text[i]
        if ch in " \t\r\n\f\v":
            j = i
            while j < n and text[j] in " \t\r\n\f\v":
                j += 1
            add("ws", i, j)
            i = j
            continue
        if ch == "-" and i + 1 < n and text[i + 1] == "-":
            j = text.find("\n", i)
            j = n if j == -1 else j
            add("comment", i, j)
            i = j
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            j = n if j == -1 else j + 2
            add("comment", i, j)
            i = j
            continue
        if ch == "'":
            j = i + 1
            while j < n:
                if engine == "hive" and text[j] == "\\":
                    j = min(j + 2, n)
                    continue
                if text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'":
                        j += 2
                        continue
                    j += 1
                    break
                j += 1
            else:
                j = n
            add("string", i, j)
            i = j
            continue
        if ch == '"' or ch == "`":
            quote = ch
            j = i + 1
            while j < n:
                if engine == "hive" and quote == '"' and text[j] == "\\":
                    j = min(j + 2, n)
                    continue
                if text[j] == quote:
                    if j + 1 < n and text[j + 1] == quote:
                        j += 2
                        continue
                    j += 1
                    break
                j += 1
            else:
                j = n
            add("string" if engine == "hive" and quote == '"' else "ident", i, j)
            i = j
            continue
        if ch in "0123456789":
            m = _NUM_RE.match(text, i)
            add("number", i, m.end())
            i = m.end()
            continue
        if ch.isalnum() or ch == "_":
            m = _WORD_RE.match(text, i)
            add("word", i, m.end())
            i = m.end()
            continue
        if ch == "|" and i + 1 < n and text[i + 1] == "|":
            add("symbol", i, i + 2)
            i += 2
            continue
        add("symbol", i, i + 1)
        i += 1
    return tokens


def code_tokens(tokens):
    """Tokens that are real SQL code (no whitespace, comments, or literals)."""
    return [t for t in tokens if t.kind in ("word", "symbol", "number", "ident")]


def find_markers(tokens):
    """Return column-1 line-comment markers with exactly the marker body.

    Indented/inline comments, extra comment text, strings and block comments do
    not match the upstream line-anchored insertion marker convention.
    """
    return [t for t in tokens
            if t.kind == "comment" and t.col == 1
            and re.fullmatch(r"--[ \t]*DIGDAG_INSERT_LINE[ \t\r]*", t.text)]


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

def _finding(rule, severity, path, tok, code, message):
    return {
        "rule": rule,
        "severity": severity,
        "path": path,
        "line": tok.line,
        "code": code,
        "message": message,
    }


def _line_text(lines, lineno):
    if 1 <= lineno <= len(lines):
        return lines[lineno - 1].rstrip("\n")
    return ""


def _next_code(code, idx):
    return code[idx] if idx < len(code) else None


def check_casts(path, code, lines, engine):
    """CAST(... AS VARCHAR) on Hive; CAST AS INT advisory narrowing."""
    out = []
    for idx, t in enumerate(code):
        if t.kind != "word" or t.text.upper() != "CAST":
            continue
        nxt = _next_code(code, idx + 1)
        if nxt is None or nxt.text != "(":
            continue
        # Walk to matching ')' tracking depth, noting a top-level AS and its type.
        depth = 0
        as_idx = None
        close_idx = None
        for k in range(idx + 1, len(code)):
            c = code[k]
            if c.text == "(":
                depth += 1
            elif c.text == ")":
                depth -= 1
                if depth == 0:
                    close_idx = k
                    break
            elif depth == 1 and c.kind == "word" and c.text.upper() == "AS":
                as_idx = k
        if as_idx is None or close_idx is None:
            continue
        type_tok = code[as_idx + 1] if as_idx + 1 < close_idx else None
        if type_tok is None or type_tok.kind != "word":
            continue
        tname = type_tok.text.upper()
        line_text = _line_text(lines, t.line)
        if engine == "hive" and tname == "VARCHAR":
            out.append(_finding(
                "hive-cast-varchar", SEV_WARNING, path, t, line_text.strip(),
                "CAST(... AS VARCHAR) in Hive: Hive uses STRING; review type mapping "
                "and length behaviour."))
        elif tname == "INT" or tname == "INTEGER":
            out.append(_finding(
                "cast-int-narrowing", SEV_ADVISORY, path, t, line_text.strip(),
                "CAST(... AS INT) may narrow values to a 32-bit range; check overflow "
                "and rounding for the source type and engine. Advisory, not universally invalid."))
    return out


def check_try_cast(path, code, lines, engine):
    """Review Trino error-suppression constructs when targeting Hive."""
    out = []
    if engine != "hive":
        return out
    for idx, t in enumerate(code):
        if t.kind != "word":
            continue
        up = t.text.upper()
        line_text = _line_text(lines, t.line).strip()
        if up == "TRY_CAST" and _next_code(code, idx + 1) is not None and code[idx + 1].text == "(":
            out.append(_finding(
                "try-cast", SEV_WARNING, path, t, line_text,
                "TRY_CAST changes invalid-input behaviour (NULL instead of error); "
                "confirm the target engine supports it and the NULL semantics match."))
        elif up == "TRY":
            nxt = _next_code(code, idx + 1)
            if nxt is not None and nxt.text == "(":
                out.append(_finding(
                    "try-function", SEV_WARNING, path, t, line_text,
                    "TRY(...) suppresses errors into NULL; review whether bad input "
                    "should be NULL or fail, and confirm the target engine."))
    return out


def check_array_constructor(path, code, lines, engine):
    """ARRAY[ constructor (Trino syntax) when targeting Hive."""
    out = []
    if engine != "hive":
        return out
    for idx, t in enumerate(code):
        if t.kind == "word" and t.text.upper() == "ARRAY":
            nxt = _next_code(code, idx + 1)
            if nxt is not None and nxt.text == "[":
                out.append(_finding(
                    "array-constructor", SEV_WARNING, path, t,
                    _line_text(lines, t.line).strip(),
                    "ARRAY[...] constructor is Trino syntax; Hive uses array(...)."))
    return out


# Functions that are review-only: behaviour differs by engine/version.
REVIEW_FUNCTIONS = {
    "JSON_FORMAT": "JSON_FORMAT output formatting and escaping may differ across engines.",
    "TO_UTF8": "TO_UTF8 returns VARBINARY; Hive equivalents may return different types.",
    "TO_HEX": "TO_HEX encoding case and binary handling may differ; verify hex output.",
    "REGEXP_LIKE": "REGEXP_LIKE syntax/flavour (Java-like vs Hive RLIKE) may differ; review pattern.",
}


def check_review_functions(path, code, lines, engine):
    out = []
    if engine != "hive":
        return out
    for idx, t in enumerate(code):
        if t.kind != "word":
            continue
        up = t.text.upper()
        if up not in REVIEW_FUNCTIONS:
            continue
        nxt = _next_code(code, idx + 1)
        if nxt is None or nxt.text != "(":
            continue
        out.append(_finding(
            "review-function-" + up.lower().replace("_", "-"), SEV_REVIEW, path, t,
            _line_text(lines, t.line).strip(), REVIEW_FUNCTIONS[up] + " Review only."))
    return out


def check_concat_operator(path, code, lines, engine):
    """Review || when targeting Hive; Trino supports concatenation."""
    out = []
    if engine != "hive":
        return out
    seen_lines = set()
    for t in code:
        if t.kind == "symbol" and t.text == "||":
            if t.line in seen_lines:
                continue
            seen_lines.add(t.line)
            out.append(_finding(
                "concat-operator", SEV_WARNING, path, t,
                _line_text(lines, t.line).strip(),
                "|| concatenation is Trino syntax; Hive uses CONCAT(). NULL propagation "
                "may differ."))
    return out


def _second_literal_argument(tokens, opening_idx):
    """Find a direct literal second argument, skipping nested expressions.

    Deliberately do not inspect literals inside computed patterns or other
    arguments: an input/replacement literal is not necessarily a regex pattern.
    """
    depth = 0
    arg_num = 0
    argument = []
    for tok in tokens[opening_idx + 1:]:
        if tok.kind == "symbol":
            if tok.text == ")" and depth == 0:
                return argument[0] if arg_num == 1 and len(argument) == 1 and argument[0].kind == "string" else None
            if tok.text == "," and depth == 0:
                if arg_num == 1:
                    return argument[0] if len(argument) == 1 and argument[0].kind == "string" else None
                arg_num += 1
                argument = []
                continue
            if tok.text in ("(", "[", "{"):
                depth += 1
            elif tok.text in (")", "]", "}"):
                depth -= 1
        argument.append(tok)
    return None


def check_regex_backslash(path, tokens, lines, engine):
    """Review odd raw backslash runs before regex escapes on target Hive only.

    Inspect direct literal second arguments of regex functions and direct
    literal RHS operands of infix RLIKE/REGEXP. Never decode or rewrite literals.
    """
    if engine != "hive":
        return []
    significant = [t for t in tokens if t.kind not in ("ws", "comment")]
    regex_fns = {"REGEXP_LIKE", "REGEXP_EXTRACT", "REGEXP_REPLACE", "RLIKE",
                 "REGEXP", "REGEXP_SPLIT", "REGEXP_COUNT", "REGEXP_POSITION",
                 "REGEXP_EXTRACT_ALL", "SPLIT"}
    meta = set(".^$*+?()[]{}|dDsSwW")
    out = []
    seen = set()
    for idx, t in enumerate(significant):
        if t.kind != "word" or t.text.upper() not in regex_fns:
            continue
        nxt = _next_code(significant, idx + 1)
        pattern = None
        if nxt is not None and nxt.kind == "symbol" and nxt.text == "(":
            pattern = _second_literal_argument(significant, idx + 1)
        elif t.text.upper() in ("RLIKE", "REGEXP") and nxt is not None and nxt.kind == "string":
            pattern = nxt
        if pattern is None or pattern.start in seen:
            continue
        if _has_single_backslash_meta(pattern.text[1:-1], meta):
            seen.add(pattern.start)
            out.append(_finding(
                "regex-single-backslash", SEV_REVIEW, path, pattern,
                _line_text(lines, pattern.line).strip(),
                "Single/unpaired backslash before a regex metacharacter or shorthand "
                "in the " + t.text.upper() + " pattern; Hive SQL-string escaping can "
                "change the regex. Review the raw literal and outer escaping layers."))
    return out


def _has_single_backslash_meta(body, meta):
    i = 0
    while i < len(body):
        if body[i] != "\\":
            i += 1
            continue
        start = i
        while i < len(body) and body[i] == "\\":
            i += 1
        if (i - start) % 2 and i < len(body) and body[i] in meta:
            return True
    return False


def _statement_leading_withs(code):
    """WITH tokens that start a statement (CTE form).

    A 'WITH (' pattern is a table property (CREATE TABLE ... WITH (...)), not a
    CTE, so it is excluded. Only a WITH with no previous code token, or right
    after ';', is treated as statement-leading.
    """
    leading = []
    for idx, t in enumerate(code):
        if t.kind != "word" or t.text.upper() != "WITH":
            continue
        nxt = _next_code(code, idx + 1)
        if nxt is not None and nxt.text == "(":
            continue
        prev = code[idx - 1] if idx > 0 else None
        if prev is None or prev.text == ";":
            leading.append(t)
    return leading


def check_marker(path, tokens, lines, engine, output_mode):
    """Marker placement checks. Hive and Trino differ in where WITH may sit.

    Hive: WITH with an output mode needs an active marker after WITH; a marker
    before WITH, or no marker at all, is a warning.
    Trino: a marker after WITH is review only, because placement is not
    parser-guaranteed. No Trino finding is emitted for a missing marker.
    Standalone mode skips placement rules; duplicate active markers still warn.
    """
    out = []
    markers = find_markers(tokens)
    if len(markers) > 1:
        out.append(_finding(
            "multiple-insert-markers", SEV_WARNING, path, markers[1],
            _line_text(lines, markers[1].line).strip(),
            "Multiple active DIGDAG_INSERT_LINE markers; review the output insertion "
            "point manually. This checker does not validate Workflow rewriting."))
    if output_mode == "standalone":
        return out
    leading = _statement_leading_withs(code_tokens(tokens))
    if not leading:
        return out
    first_with = leading[0]

    if engine == "hive":
        if not markers:
            out.append(_finding(
                "marker-missing-hive-with", SEV_WARNING, path, first_with,
                _line_text(lines, first_with.line).strip(),
                "Hive WITH with output mode '%s' and no active %s marker; check where "
                "the output DDL/DML is inserted." % (output_mode, MARKER)))
        for m in markers:
            if m.start < first_with.start:
                out.append(_finding(
                    "marker-before-with-hive", SEV_WARNING, path, m,
                    _line_text(lines, m.line).strip(),
                    "%s appears before WITH on Hive; WITH must lead the statement, "
                    "so review the insertion position." % MARKER))
    elif engine == "trino":
        for m in markers:
            if m.start > first_with.start:
                out.append(_finding(
                    "marker-after-with-trino", SEV_REVIEW, path, m,
                    _line_text(lines, m.line).strip(),
                    "%s appears after WITH on Trino; placement is not parser-guaranteed, "
                    "so verify the inserted statement manually." % MARKER))
    return out


CHECKS = (
    check_casts,
    check_try_cast,
    check_array_constructor,
    check_review_functions,
    check_concat_operator,
)


def check_text(path, text, engine, output_mode):
    """Run all checks on a text. Returns list of findings."""
    tokens = tokenize(text, engine)
    code = code_tokens(tokens)
    lines = text.splitlines()
    findings = []
    for chk in CHECKS:
        findings.extend(chk(path, code, lines, engine))
    findings.extend(check_regex_backslash(path, tokens, lines, engine))
    findings.extend(check_marker(path, tokens, lines, engine, output_mode))
    findings.sort(key=lambda f: (f["line"], f["rule"]))
    return findings


# ---------------------------------------------------------------------------
# File handling and CLI
# ---------------------------------------------------------------------------

class FileProblem(Exception):
    pass


def read_file(path):
    if not os.path.exists(path):
        raise FileProblem("file not found: %s" % path)
    if os.path.isdir(path):
        raise FileProblem("path is a directory, not a file: %s" % path)
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError as exc:
        raise FileProblem("cannot read %s: %s" % (path, exc.strerror or exc))
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        raise FileProblem("file is not valid UTF-8: %s" % path)


def build_parser():
    ap = argparse.ArgumentParser(
        description="Read-only offline heuristic SQL migration risk checker. "
                    "Not a full SQL/Workflow validator.")
    ap.add_argument("--engine", required=True, choices=ENGINES)
    ap.add_argument("--output-mode", default="standalone", choices=OUTPUT_MODES,
                    help="output insertion mode (default: standalone)")
    ap.add_argument("--json", action="store_true", help="emit JSON report")
    ap.add_argument("files", nargs="+", metavar="FILE")
    return ap


def run(argv):
    """Return (exit_code, report, want_json).

    report is None only when argument parsing failed or --help was requested;
    argparse has already printed its message in that case.
    """
    ap = build_parser()
    try:
        args = ap.parse_args(argv)
    except SystemExit as exc:
        return (EXIT_OK if exc.code == 0 else EXIT_FAIL), None, False

    report = {
        "tool": "check_sql.py",
        "engine": args.engine,
        "output_mode": args.output_mode,
        "disclaimer": DISCLAIMER,
        "files_checked": [],
        "findings": [],
        "file_errors": [],
    }
    failed = False
    for path in args.files:
        try:
            text = read_file(path)
        except FileProblem as exc:
            report["file_errors"].append({"path": path, "message": str(exc)})
            failed = True
            continue
        report["files_checked"].append(path)
        report["findings"].extend(
            check_text(path, text, args.engine, args.output_mode))

    want_json = bool(args.json)
    if failed:
        report["status"] = "error"
        return EXIT_FAIL, report, want_json
    if report["findings"]:
        report["status"] = "warnings"
        return EXIT_WARN, report, want_json
    report["status"] = "no_findings"
    return EXIT_OK, report, want_json


def _format_text(report):
    lines = []
    lines.append("check_sql.py engine=%s output_mode=%s" % (report["engine"], report["output_mode"]))
    for f in report["findings"]:
        lines.append("%s:%d [%s/%s] %s" % (f["path"], f["line"], f["severity"], f["rule"], f["message"]))
        if f["code"]:
            lines.append("    > " + f["code"])
    lines.append("files checked: %d, file errors: %d, findings: %d" % (
        len(report["files_checked"]), len(report["file_errors"]), len(report["findings"])))
    lines.append(report["disclaimer"])
    return "\n".join(lines)


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    code, report, want_json = run(argv)
    if report is None:
        return code
    if want_json:
        sys.stdout.write(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    else:
        for f in report["file_errors"]:
            sys.stderr.write("ERROR %s: %s\n" % (f["path"], f["message"]))
        sys.stdout.write(_format_text(report) + "\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
