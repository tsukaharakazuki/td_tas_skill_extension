#!/usr/bin/env python3
"""Validate a local analytics project, optionally compiling reviewed JSON config.

Run with ``python3 -I validate_project.py /absolute/project [--compile-config]``.
Only the Python standard library is used. No TD commands or remote calls are run.
"""

import argparse
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


SLUG = re.compile(r"[a-z0-9][a-z0-9_-]{0,63}\Z", re.ASCII)
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z", re.ASCII)
HOST_LABEL = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\Z", re.ASCII)
PLACEHOLDER = re.compile(r"REPLACE_ME|@@", re.IGNORECASE)
ADAPTER_PLACEHOLDER = re.compile(r"\b(?:REPLACE|TODO)(?:_[A-Za-z0-9_]+)?\b|@@", re.IGNORECASE)
GENERATED = {"config/params.yml", "tdx.json"}
REQUIRED = ("config/params.yml", "tdx.json", "ad_purchase_analytics.dig", "dashboard_output/mapping.json")


def check_path(path):
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("project path must be absolute and must not contain '..'")
    for part in reversed((path,) + tuple(path.parents)):
        if part.is_symlink():
            raise ValueError("symlinks are not allowed: {}".format(part))


def walk_error(error):
    raise error


def project_files(project):
    """Reject links without following them, including links in otherwise unused dirs."""
    check_path(project)
    if not project.is_dir():
        raise ValueError("project directory does not exist: {}".format(project))
    files = []
    for directory, directories, names in os.walk(project, followlinks=False, onerror=walk_error):
        for name in sorted(directories + names):
            path = Path(directory) / name
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                raise ValueError("project contains a symlink: {}".format(path))
            if stat.S_ISREG(mode):
                files.append(path)
            elif not stat.S_ISDIR(mode):
                raise ValueError("project contains a nonregular entry: {}".format(path))
    return sorted(files)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key: {}".format(key))
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError("nonstandard JSON constant: {}".format(value))


def read_object(path, raw_bytes=None):
    text = path.read_text(encoding="utf-8") if raw_bytes is None else raw_bytes.decode("utf-8")
    value = json.loads(text, object_pairs_hook=unique_object, parse_constant=reject_constant)
    if not isinstance(value, dict):
        raise ValueError("JSON document must be an object: {}".format(path))
    return value


def forbidden_keys(value, path="config", forbid_profile=False):
    errors = []
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", key).lower()
            normalized = re.sub(r"[^a-z0-9]+", "_", normalized).strip("_")
            pieces = set(normalized.split("_"))
            secret = (bool(pieces & {"secret", "secrets", "password", "passwd", "token", "tokens",
                                    "credential", "credentials"})
                      or "api_key" in normalized or "apikey" in normalized
                      or "private_key" in normalized)
            override = forbid_profile and bool(pieces & {"profile", "profiles", "site"})
            location = "{}.{}".format(path, key)
            if secret or override:
                errors.append("{}: secret/account override keys are not allowed".format(location))
            errors.extend(forbidden_keys(child, location, forbid_profile))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            errors.extend(forbidden_keys(child, "{}[{}]".format(path, index), forbid_profile))
    return errors


def valid_host(host):
    return (isinstance(host, str) and 0 < len(host) <= 253
            and all(HOST_LABEL.fullmatch(label) for label in host.split(".")))


def active_sql(text):
    """Remove SQL comments, retaining quoted strings/identifiers and line breaks."""
    output = []
    index = 0
    quote = None
    block_depth = 0
    while index < len(text):
        pair = text[index:index + 2]
        char = text[index]
        if block_depth:
            if pair == "/*":
                block_depth += 1
                index += 2
            elif pair == "*/":
                block_depth -= 1
                index += 2
            else:
                output.append("\n" if char == "\n" else " ")
                index += 1
        elif quote:
            output.append(char)
            index += 1
            if char == quote:
                if index < len(text) and text[index] == quote:
                    output.append(text[index])
                    index += 1
                else:
                    quote = None
        elif pair == "--":
            end = text.find("\n", index)
            if end < 0:
                break
            output.append("\n")
            index = end + 1
        elif pair == "/*":
            output.append(" ")
            block_depth = 1
            index += 2
        else:
            output.append(char)
            if char in {"'", '"', "`"}:
                quote = char
            index += 1
    return "".join(output)


def schema_errors(config):
    """Allow additional nonsecret QA/mapping fields without weakening core fields."""
    errors = forbidden_keys(config, "config/project.json")

    def invalid(field, message):
        errors.append("config/project.json: {} {}".format(field, message))

    configured = config.get("configured")
    if type(configured) is not bool:
        invalid("configured", "must be a boolean")
    name = config.get("project_name")
    if not isinstance(name, str) or not SLUG.fullmatch(name):
        invalid("project_name", "must be a lowercase ASCII slug of 1-64 characters")
    for field in ("output_database", "table_prefix"):
        value = config.get(field)
        if not isinstance(value, str) or not IDENTIFIER.fullmatch(value) or PLACEHOLDER.search(value):
            invalid(field, "must be a nonplaceholder unquoted SQL identifier ([A-Za-z_][A-Za-z0-9_]*)")
        elif field == "table_prefix" and len(value) > 20:
            invalid(field, "must be at most 20 characters")
    web_table = config.get("web_table")
    if (not isinstance(web_table, str) or len(web_table.split(".")) != 2
            or PLACEHOLDER.search(web_table)
            or not all(IDENTIFIER.fullmatch(part) for part in web_table.split("."))):
        invalid("web_table", "must have exactly two SQL identifiers: database.table")
    for field, choices in (("purchase_mode", ("web", "separate")), ("session_mode", ("window", "sdk"))):
        if config.get(field) not in choices:
            invalid(field, "must be one of {}".format(", ".join(choices)))
    if type(config.get("ad_costs_enabled")) is not bool:
        invalid("ad_costs_enabled", "must be a boolean")
    if config.get("refresh_strategy") != "full_retained_history":
        invalid("refresh_strategy", "must be full_retained_history; incremental refresh is not implemented")
    for field in ("session_timeout_seconds", "lookback_days"):
        value = config.get(field)
        if type(value) is not int or value <= 0:
            invalid(field, "must be a positive integer (not a boolean)")
    dates = {}
    for field in ("report_start", "report_end"):
        value = config.get(field)
        try:
            if not isinstance(value, str) or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
                raise ValueError("not an ISO calendar date")
            dates[field] = date.fromisoformat(value)
        except ValueError:
            invalid(field, "must be a valid ISO date (YYYY-MM-DD)")
    if len(dates) == 2 and dates["report_start"] >= dates["report_end"]:
        invalid("report_start", "must be earlier than report_end (exclusive end)")
    timezone = config.get("timezone")
    try:
        if not isinstance(timezone, str) or not timezone.strip():
            raise ValueError("missing timezone")
        ZoneInfo(timezone)
    except (ZoneInfoNotFoundError, ValueError):
        invalid("timezone", "must be an available IANA timezone, e.g. Asia/Tokyo")
    currency = config.get("currency")
    if not isinstance(currency, str) or not re.fullmatch(r"[A-Z]{3}", currency, re.ASCII):
        invalid("currency", "must be one ISO three-letter uppercase currency code (single currency)")
    hosts = config.get("internal_hosts")
    if not isinstance(hosts, list) or not hosts:
        invalid("internal_hosts", "must be a nonempty list of hostnames")
    else:
        for index, host in enumerate(hosts):
            if not valid_host(host):
                invalid("internal_hosts[{}]".format(index),
                        "must be a plain ASCII hostname without a scheme, port, wildcard, whitespace or SQL")
    dashboard = config.get("dashboard_template")
    if not isinstance(dashboard, dict):
        invalid("dashboard_template", "must be an object with repository, commit and sha256")
    else:
        repository = dashboard.get("repository")
        if (not isinstance(repository, str) or not repository.strip()
                or ADAPTER_PLACEHOLDER.search(repository)):
            invalid("dashboard_template.repository", "must name a nonplaceholder repository")
        for field, length in (("commit", 40), ("sha256", 64)):
            value = dashboard.get(field)
            if field not in dashboard:
                invalid("dashboard_template.{}".format(field), "is required (null is allowed only before review)")
            elif value is None and configured is False:
                continue
            elif not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{%d}" % length, value):
                invalid("dashboard_template.{}".format(field), "must be pinned to {} hex characters".format(length))
    return errors


def compiled_params(config, config_sha256):
    """Emit only JSON-formatted YAML scalars; no YAML parser or runtime -p needed."""
    scalar = lambda value: json.dumps(value, ensure_ascii=True, allow_nan=False)
    values = [
        ("config_sha256", config_sha256),
        ("table_prefix", config["table_prefix"]),
        ("web_table", config["web_table"]),
        ("purchase_mode", config["purchase_mode"]),
        ("ad_costs_enabled", config["ad_costs_enabled"]),
        ("refresh_strategy", config["refresh_strategy"]),
        ("session_mode", config["session_mode"]),
        ("session_timeout_seconds", config["session_timeout_seconds"]),
        ("lookback_days", config["lookback_days"]),
        ("report_start", config["report_start"]),
        ("report_end", config["report_end"]),
        ("report_timezone", config["timezone"]),
        ("currency", config["currency"]),
        ("internal_hosts_sql", "(" + ",".join("'{}'".format(host.lower()) for host in config["internal_hosts"]) + ")"),
    ]
    lines = ["# Generated from config/project.json; change that file and recompile.",
             "configuration_reviewed: true", "td:",
             "  database: " + scalar(config["output_database"]), "  engine: " + scalar("presto")]
    lines.extend("{}: {}".format(key, scalar(value)) for key, value in values)
    return "\n".join(lines) + "\n"


def atomic_write(path, text):
    """Replace a regular local config file rather than following a link/hardlink."""
    check_path(path)
    if path.exists() and not path.is_file():
        raise ValueError("generated config destination is not a regular file: {}".format(path))
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="\n",
                                         dir=path.parent, prefix="." + path.name + ".",
                                         delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        check_path(path)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def inspect_project(project, compiling=False):
    files = project_files(project)
    errors = []
    try:
        config = read_object(project / "config" / "project.json")
    except (OSError, UnicodeError, ValueError) as error:
        return None, ["config/project.json: {}".format(error)]
    errors.extend(schema_errors(config))
    if config.get("configured") is False:
        errors.append("config/project.json: configured is false; complete review and explicitly set it to true")
    for relative in REQUIRED:
        path = project / relative
        if not path.is_file() and not (compiling and relative in GENERATED and not path.exists()):
            errors.append("missing required regular file: {}".format(relative))
    tdx = project / "tdx.json"
    if tdx.is_file():
        try:
            errors.extend(forbidden_keys(read_object(tdx), "tdx.json", forbid_profile=True))
        except (OSError, UnicodeError, ValueError) as error:
            errors.append("tdx.json: {}".format(error))
    adapters = ["queries/00_web.sql"]
    if config.get("purchase_mode") == "separate":
        adapters.append("queries/00_orders_separate.sql")
    if config.get("ad_costs_enabled") is True:
        adapters.append("queries/00_costs.sql")
    if config.get("configured") is True:
        for relative in adapters:
            path = project / relative
            if not path.is_file():
                errors.append("missing configured SQL adapter: {}".format(relative))
            else:
                try:
                    if ADAPTER_PLACEHOLDER.search(active_sql(path.read_text(encoding="utf-8"))):
                        errors.append("{}: unresolved REPLACE/@@/TODO adapter token".format(relative))
                except (OSError, UnicodeError) as error:
                    errors.append("{}: {}".format(relative, error))
    for path in files:
        relative = path.relative_to(project).as_posix()
        if path.suffix.lower() not in {".dig", ".sql", ".yml", ".yaml"}:
            continue
        if path.relative_to(project).parts[0] in {"docs", "references"}:
            continue  # Reference documentation is not executable project configuration.
        if relative == "queries/00_orders_separate.sql" and config.get("purchase_mode") != "separate":
            continue  # The unused separate-purchase adapter is intentionally unconfigured.
        if relative == "queries/00_costs.sql" and config.get("ad_costs_enabled") is not True:
            continue  # Optional cost adapter is inactive while costs are disabled.
        if compiling and relative == "config/params.yml":
            continue  # This file is safely regenerated after every other check passes.
        try:
            text = path.read_text(encoding="utf-8")
            if path.suffix.lower() == ".sql":
                text = active_sql(text)
            if PLACEHOLDER.search(text):
                errors.append("{}: unresolved REPLACE_ME/@@ placeholder".format(relative))
        except (OSError, UnicodeError) as error:
            errors.append("{}: {}".format(relative, error))
    return config, errors


def validate(project, compile_config=False):
    config, errors = inspect_project(project, compiling=compile_config)
    if not errors and compile_config:
        config_path = project / "config" / "project.json"
        raw_config = config_path.read_bytes()
        if read_object(config_path, raw_config) != config:
            return ["config/project.json changed during validation; rerun before compiling"]
        digest = hashlib.sha256(raw_config).hexdigest()
        atomic_write(project / "config" / "params.yml", compiled_params(config, digest))
        tdx = {"database": config["output_database"], "workflow_project": config["project_name"]}
        atomic_write(project / "tdx.json", json.dumps(tdx, indent=2, ensure_ascii=True) + "\n")
        _, errors = inspect_project(project)
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="absolute project directory")
    parser.add_argument("--compile-config", action="store_true",
                        help="compile reviewed project.json to params.yml and account-neutral tdx.json")
    arguments = parser.parse_args(argv)
    try:
        errors = validate(arguments.project, arguments.compile_config)
    except (OSError, UnicodeError, ValueError) as error:
        errors = [str(error)]
    if errors:
        for error in errors:
            print("ERROR: " + error, file=sys.stderr)
        return 1
    print("{} project: {}".format("Compiled and validated" if arguments.compile_config else "Validated", arguments.project))
    print("Local checks only: source mappings, QA results and dashboard provenance still need human review.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
