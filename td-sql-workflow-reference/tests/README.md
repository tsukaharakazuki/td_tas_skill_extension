# check_sql.py tests

`tests/test_check_sql.py` tests `scripts/check_sql.py`, a read-only, offline,
heuristic SQL migration risk checker (Python stdlib only).

## Run

Use an absolute path and `-I` from a trusted directory outside a downloaded
clone (for example a separate scratch directory under `/tmp`). The tests need
no engine, no network, and no query execution. They load only the authored
checker by a controlled path with `importlib`; CLI tests invoke it using
`python3 -I` in temporary directories. Tests write scratch fixtures, but the
checker itself never writes files. Bytecode output is disabled for the import.

```sh
python3 -I /abs/path/to/td-sql-workflow-reference/tests/test_check_sql.py -v
```

The suite has **73 tests**:

- Lexical: comments, doubled and Hive backslash-escaped quotes, raw backslash
  preservation, quoted identifiers, Japanese identifiers and Unicode digits,
  keyword boundaries, `CASE` vs `CAST`, line numbers, unterminated comments.
- Markers: column-1 active markers, rejected inline/indented/trailing-code
  markers, fake markers in strings and block comments, duplicate warnings,
  Hive WITH rules, Trino review rule, standalone placement, table properties.
- Rules: Hive migration findings, clean legitimate Trino syntax, INT narrowing
  advisory, regex shorthands/metacharacters, odd/even backslash runs, infix
  `RLIKE`/`REGEXP`, and pattern-only inspection (not input/replacement literals).
- Files and CLI: missing/directory/non-UTF-8 files, exit codes 0/1/2, argument
  errors, all output modes and the standalone default, Unicode SQL, multiple
  files, JSON reports for clean/warning/file-error runs.

## CLI under test

```text
python3 -I /abs/path/to/scripts/check_sql.py --engine hive|trino
    [--output-mode standalone|create-table|insert-into] [--json] FILE [FILE ...]
```

`--output-mode` defaults to `standalone`. Exit codes: `0` no heuristic findings,
`1` one or more findings (including advisory ones), `2` file or argument failure.
File failure takes precedence; the other files are still checked and reported.

Migration checks for TRY_CAST/TRY, `ARRAY[`, `||`, review functions and regex
backslashes apply **only to target Hive**. Those constructs are not flagged
merely for being valid Trino syntax. `CAST(... AS INT)` is advisory on both
engines: check narrowing, overflow and rounding for the source type/engine, not
an assumption that all such casts are invalid or always truncate fractions.

## Known limits

- Heuristic lexical scan only: not a full SQL parser, Digdag/Workflow validator,
  runtime check or semantic-equivalence check. A clean run does not mean the SQL
  runs successfully. No query is executed and nothing is automatically rewritten.
- Dynamic SQL is not expanded: `${...}` templates and generated text can produce
  false positives or false negatives. Nested CTE scopes and multi-statement
  insertion scopes are not resolved. Placement uses the first statement-leading
  `WITH` (file start or after `;`) only; table-property `WITH (...)` is excluded.
- An active marker is a **column-1** `--` line comment whose body is exactly
  `DIGDAG_INSERT_LINE` (horizontal whitespace around the body is allowed).
  Indentation, inline comments, extra trailing text, strings and block comments
  do not count. Duplicate active markers warn in all modes; placement checks
  apply only to create-table/insert-into. A Hive statement with a leading `WITH`
  needs an active marker in those modes; standalone (Console) runs do not.
  Trino placement after `WITH` is review only, not parser-guaranteed.
- The lexer models common Hive single/double-quoted strings with backslash
  escapes and common Trino single-quoted strings with doubled quotes. Raw token
  text is preserved: escapes are used to locate boundaries, never decoded.
  Double quotes are treated as identifiers on Trino and strings on Hive;
  backticks as identifiers. Engine/version/session-specific quoting, nested
  block comments and dollar-quoted strings are not fully supported. Malformed
  or unterminated constructs can hide later tokens; syntax is not validated.
- Hive regex checks inspect only a **direct literal second argument** of listed
  regex functions (including `split`) or a direct literal RHS of infix
  `RLIKE`/`REGEXP`. Input and replacement literals are not patterns. Computed,
  parenthesized or dynamically generated patterns can be missed. Odd raw
  backslash runs before metacharacters or `d/D/s/S/w/W` are review items, not
  proof of a broken regex; outer YAML/JavaScript escaping is not evaluated.
- Review-function findings are name-based, without type/schema/version data.
- Files must be UTF-8. Unicode identifiers/digits are scanned without requiring
  them to be valid SQL; successful tokenization is not syntax acceptance.
- The checker has no network access, writes, query execution, or automatic fixes.
