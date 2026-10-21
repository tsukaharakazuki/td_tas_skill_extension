#!/usr/bin/env python3
"""Render aggregate-only results using the pinned TD HTML template. No network calls."""
import argparse
import hashlib
import html
import json
import re
import sys
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path

FORBIDDEN_KEYS = {"td_client_id", "cookie", "cookie_id", "member_id", "user_id", "session_id",
                  "session_key", "url", "referrer", "email", "order_id", "event_key", "api_key", "token"}
COUNT_FIELDS = ("acquired_cookies", "logged_cookies", "purchasing_cookies", "orders", "unpriced_orders")
MONEY_FIELDS = ("known_sales", "sales", "spend")
TEMPLATE_SHA = "f6f72d7512ea389d03ec09a31f7d1e034f6737395b7a81ebf4c4cabdc0111ef2"


def read_json(path):
    if path.is_symlink():
        raise ValueError(f"Symlink is not allowed: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def number(value, nullable=False):
    if value is None and nullable:
        return None
    if isinstance(value, bool) or value is None:
        raise ValueError("Expected a finite number, not null/bool")
    try:
        result = Decimal(str(value))
    except InvalidOperation as exc:
        raise ValueError("Invalid number") from exc
    if not result.is_finite():
        raise ValueError("Non-finite number")
    return result


def check_privacy(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in FORBIDDEN_KEYS:
                raise ValueError(f"Raw identifier/private field is not allowed in dashboard data: {key}")
            check_privacy(child)
    elif isinstance(value, list):
        for child in value:
            check_privacy(child)


def validate_bundle(data, config, config_bytes, demo):
    if data.get("schema_version") != 1 or data.get("demo") is not demo:
        raise ValueError("Bundle version/demo flag mismatch")
    check_privacy(data)
    manifest = data["manifest"]
    if not re.fullmatch(r"\d+_\d+", manifest["run_id"]):
        raise ValueError("run_id must be <session_unixtime>_<attempt_id>")
    epoch, attempt = (int(part) for part in manifest["run_id"].split("_"))
    if epoch != manifest["observation_end"] or attempt != manifest["attempt_id"]:
        raise ValueError("Manifest cutoff/attempt mismatch")
    if not demo:
        if config.get("configured") is not True:
            raise ValueError("Project is not configured")
        if manifest.get("project_name") != config["project_name"]:
            raise ValueError("Project mismatch")
        if manifest.get("config_sha256") != hashlib.sha256(config_bytes).hexdigest():
            raise ValueError("Config differs from the completed run")
        if manifest.get("qa_passed") is not True or number(data["qa"].get("hard_errors")) != 0:
            raise ValueError("QA must pass before rendering")
    for name in ("cohort", "inflow", "lookback"):
        rows = data[name]
        if not isinstance(rows, list) or len(rows) > 20000:
            raise ValueError(f"{name} must be an aggregate list with <=20000 rows")
        if manifest["row_counts"].get(name) != len(rows):
            raise ValueError(f"Incomplete/truncated result: {name}")
    keys = set()
    for row in data["cohort"]:
        dims = ("acquisition_date", "source", "medium", "campaign", "content", "term", "currency")
        key = tuple(row[field] for field in dims)
        if key in keys:
            raise ValueError("Duplicate cohort grain")
        keys.add(key)
        if row["currency"] != config["currency"]:
            raise ValueError("Mixed currency")
        for field in COUNT_FIELDS:
            value = number(row[field])
            if value < 0 or value != value.to_integral_value():
                raise ValueError(f"{field} must be a nonnegative integer")
        for field in MONEY_FIELDS:
            number(row[field], nullable=True)
        if number(row["logged_cookies"]) > number(row["acquired_cookies"]):
            raise ValueError("Identified-cookie count exceeds acquired cookies")
        if number(row["purchasing_cookies"]) > number(row["logged_cookies"]):
            raise ValueError("Purchasing-cookie count exceeds identified cookies")
        if number(row["unpriced_orders"]) > 0 and row["sales"] is not None:
            raise ValueError("Unpriced orders must not be presented as complete sales")
    for name in ("inflow", "lookback"):
        for row in data[name]:
            if not isinstance(row.get("label"), str):
                raise ValueError(f"{name} rows require a public aggregate label")
            number(row["orders"])
            number(row["sales"], nullable=True)


def totals(rows):
    result = {field: sum((number(row[field]) for row in rows), Decimal(0)) for field in COUNT_FIELDS}
    for field in MONEY_FIELDS:
        result[field] = (None if any(row[field] is None for row in rows)
                         else sum((number(row[field]) for row in rows), Decimal(0)))
    result["roas_pct"] = (result["sales"] / result["spend"] * 100
                          if result["sales"] is not None and result["spend"] is not None
                          and result["spend"] > 0 and result["unpriced_orders"] == 0 else None)
    for key, numerator, denominator in (("login_rate_pct", "logged_cookies", "acquired_cookies"),
                                        ("purchase_rate_pct", "purchasing_cookies", "acquired_cookies")):
        result[key] = result[numerator] / result[denominator] * 100 if result[denominator] else None
    return result


def esc(value):
    return html.escape(str(value), quote=True)


def formatted(value, kind, currency):
    if value is None:
        return "—"
    if kind == "text":
        return esc(value)
    value = number(value)
    if kind == "integer":
        return f"{value:,.0f}"
    if kind == "percent":
        return f"{value:,.1f}%"
    if kind == "money":
        return esc(currency) + " " + f"{value:,.2f}"
    raise ValueError(f"Unknown format: {kind}")


def table_html(rows, columns, currency):
    head = "".join("<th>" + esc(col["label"]) + "</th>" for col in columns)
    body = []
    for row in rows:
        body.append("<tr>" + "".join('<td class="' + ("tas-num" if col["format"] != "text" else "")
                    + '">' + formatted(row.get(col["field"]), col["format"], currency) + "</td>"
                    for col in columns) + "</tr>")
    if not rows:
        body.append('<tr><td colspan="' + str(len(columns)) + '">対象データなし</td></tr>')
    return '<div style="overflow-x:auto"><table class="tas-table"><thead><tr>' + head + "</tr></thead><tbody>" + "".join(body) + "</tbody></table></div>"


def render(template, mapping, config, data, demo):
    currency = config["currency"]
    rows = data["cohort"]
    values = totals(rows)
    title = ("【合成データ・デモ】" if demo else "") + mapping["title"]
    manifest = data["manifest"]
    observed = datetime.fromtimestamp(manifest["observation_end"], timezone.utc).isoformat()
    lead = (f"獲得期間 {config['report_start']} 以上 / {config['report_end']} 未満 ({config['timezone']})"
            f"｜購買観測終了 {observed} 未満｜run {manifest['run_id']}")
    pieces = ['<main class="tas-main">', '<h1 class="tas-page-title">' + esc(title) + '</h1>',
              '<p class="tas-lead">' + esc(lead) + '</p>']
    if demo:
        pieces.append('<blockquote class="tas-callout">全数値は動作確認用の架空データです。実データの集計・TD上のSQL検証は行っていません。</blockquote>')
    pieces.append('<section><h2 class="tas-section-title">初回landingコホート</h2><div class="tas-kpis">')
    for spec in mapping["kpis"]:
        field = spec["field"]
        if field not in values:
            raise ValueError(f"Define an explicit aggregator before adding KPI: {field}")
        label = spec["label"]
        if field == "logged_cookies":
            label = config.get("identity_observation_label", "会員ID観測") + "Cookie"
        pieces.append('<div class="tas-kpi"><div class="tas-kpi-label">' + esc(label)
                      + '</div><div class="tas-kpi-value">' + formatted(values[field], spec["format"], currency)
                      + '</div><div class="tas-kpi-note">獲得コホートを観測終了まで追跡</div></div>')
    pieces.append('</div></section>')
    bars = mapping["bars"]
    if bars["metric"] not in COUNT_FIELDS or bars["dimension"] not in {"source", "medium", "campaign", "acquisition_date"}:
        raise ValueError("Bars require an additive count and public cohort dimension")
    groups = {}
    for row in rows:
        label = str(row[bars["dimension"]])
        groups[label] = groups.get(label, Decimal(0)) + number(row[bars["metric"]])
    max_value = max(groups.values(), default=Decimal(1)) or Decimal(1)
    colors = ("primary-1", "primary-2", "secondary-2", "secondary-1", "accent-5", "accent-1", "accent-2", "accent-4")
    pieces.append('<section><h2 class="tas-section-title">' + esc(bars["label"]) + '</h2><div class="tas-bars">')
    for index, (label, value) in enumerate(sorted(groups.items(), key=lambda item: (-item[1], item[0]))[:10]):
        width = min(Decimal(100), max(Decimal(0), value / max_value * 100))
        pieces.append('<div class="tas-bar-row"><span style="overflow-wrap:anywhere">' + esc(label)
                      + '</span><div class="tas-bar-track"><div class="tas-bar-fill" style="width:'
                      + f'{width:.2f}' + '%;background:var(--tas-' + colors[index % len(colors)]
                      + ')"></div></div><span>' + formatted(value, "integer", currency) + '</span></div>')
    pieces.append('</div></section><section><h2 class="tas-section-title">獲得日・施策別詳細</h2>')
    pieces.append(table_html(rows, mapping["table_columns"], currency) + '</section>')
    for name, label in (("inflow", "初回session内の流入関連（施策間は非加算）"),
                        ("lookback", f"購入前{config['lookback_days']}日 last-touch（別モデル）")):
        pieces.append('<section><h2 class="tas-section-title">' + esc(label) + '</h2>')
        pieces.append(table_html(data[name], [{"field": "label", "label": "施策", "format": "text"},
                     {"field": "orders", "label": "関連注文" if name == "inflow" else "注文", "format": "integer"},
                     {"field": "sales", "label": "関連売上" if name == "inflow" else "売上", "format": "money"}], currency) + '</section>')
    pieces.append('<section><h2 class="tas-section-title">定義と注意事項</h2><ul>')
    pieces.extend('<li>' + esc(note) + '</li>' for note in mapping["notes"])
    pieces.append('</ul><p>Generated with Treasure Work</p></section></main>')
    if len(re.findall(r'<main\b', template)) != 1 or template.count('</main>') != 1:
        raise ValueError("Unexpected upstream template structure")
    result = re.sub(r'<main\b[^>]*>.*?</main>', lambda _: "\n".join(pieces), template, flags=re.S)
    result = re.sub(r'<title>.*?</title>', lambda _: '<title>' + esc(title) + ' | Treasure AI</title>', result, flags=re.S)
    return result.replace('更新日: YYYY-MM-DD', '更新日: ' + observed[:10])


def write_atomic(path, content):
    if path.is_symlink() or path.parent.is_symlink():
        raise ValueError("Refusing symlink output")
    if path.exists():
        path.read_bytes()  # Inspect an existing target before replacing it.
    temporary = path.with_name(path.name + '.new')
    with temporary.open('x', encoding='utf-8') as handle:
        handle.write(content)
    temporary.replace(path)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--demo', action='store_true')
    parser.add_argument('--promote', action='store_true')
    args = parser.parse_args(argv)
    try:
        project = args.project.absolute()
        if any(path.is_symlink() for path in [project, *project.parents]):
            raise ValueError("Project path must not use symlinks")
        if args.demo and args.promote:
            raise ValueError("Demo cannot be promoted")
        config_path = project / 'config/project.json'
        config = read_json(config_path)
        config_bytes = config_path.read_bytes()
        mapping = read_json(project / 'dashboard_output/mapping.json')
        data = read_json(args.data)
        validate_bundle(data, config, config_bytes, args.demo)
        template_path = project / 'dashboard_template/template.html'
        if template_path.is_symlink():
            raise ValueError("Template must not be a symlink")
        template_bytes = template_path.read_bytes()
        expected = config['dashboard_template'].get('sha256') or (TEMPLATE_SHA if args.demo else None)
        if expected is None or hashlib.sha256(template_bytes).hexdigest() != expected:
            raise ValueError("Pinned template hash mismatch")
        text = render(template_bytes.decode('utf-8'), mapping, config, data, args.demo)
        if '<script' in text.lower() or 'Prepared by Treasure Data' not in text:
            raise ValueError("Dashboard must retain TD credit and contain no script")
        run_id = data['manifest']['run_id']
        destination = project / 'dashboard_output/runs' / run_id
        for path in (project / 'dashboard_output', project / 'dashboard_output/runs', destination, project / 'runs'):
            if path.is_symlink():
                raise ValueError("Output symlink is not allowed")
        output = destination / 'index.html'
        if output.exists() and (output.is_symlink() or output.read_text(encoding='utf-8') != text):
            raise ValueError("Run HTML already exists with different content; use a new run")
        destination.mkdir(parents=True, exist_ok=True)
        if not output.exists():
            output.write_text(text, encoding='utf-8')
        if args.promote:
            latest = project / 'runs/latest_success.json'
            if latest.exists():
                old = read_json(latest)
                if tuple(map(int, old['run_id'].split('_'))) > tuple(map(int, run_id.split('_'))):
                    raise ValueError("An older run cannot replace a newer successful run")
            (project / 'runs').mkdir(exist_ok=True)
            write_atomic(project / 'dashboard_output/index.html', text)
            manifest = dict(data['manifest'], html_sha256=hashlib.sha256(text.encode()).hexdigest())
            write_atomic(latest, json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        print(str(output))
        return 0
    except (ValueError, KeyError, TypeError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
