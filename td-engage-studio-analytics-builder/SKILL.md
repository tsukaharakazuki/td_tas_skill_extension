---
name: td-engage-studio-analytics-builder
description: Use when the user wants to build, customize, or debug an Engage Studio delivery report workflow — email and LINE delivery results aggregated per message and overall — using the bundled td_engage_studio_analytics workflow template (tsukaharakazuki/td_tas_skill_extension/td-engage-studio-analytics-builder). Discovers delivery_email_* / delivery_line_* databases with read-only tdx queries, checks actual columns against the docs (time = send time, campaign_id vs custom_event_id, test_mode, is_bot_event, error_events, LINE log format), always asks whether LINE is being sent, sets up optional LINE OA Insights for opens/clicks, writes config/*.yml, builds the Treasure AI branded HTML dashboard with channel/date/message filters, and configures the daily HTML mail report sent from the workflow. Trigger on 「Engage Studioのレポート」「Engage配信結果を集計」「メール配信レポートWF」「開封率・クリック率を集計」「LINE配信結果」「LINE OA Insights」「Engage Studio Dashboard」「配信結果の日次メール」「td_engage_studio_analytics」「delivery_email_」「delivery_line_」, Engage Studio analytics, email campaign reporting workflow.
---

# Engage Studio Analytics Builder

Configure the `td_engage_studio_analytics` Treasure Workflow: it aggregates Engage Studio email (and optionally LINE) delivery logs into per-message and per-day tables, feeds a branded HTML dashboard, and can send a daily HTML mail report. Customer-specific settings live in `config/*.yml`; SQL and dig are generic. Your job: discover the customer's real data, interview, fill configs, verify with read-only queries, and hand over a safe deploy path.

- Template: `templates/project/` next to this SKILL.md
  (https://github.com/tsukaharakazuki/td_tas_skill_extension/tree/main/td-engage-studio-analytics-builder/templates/project)
- Docs in `templates/project/docs/` — read the relevant one before editing:
  - `source_schema.md` — source columns, **differences between docs and real data**, check queries
  - `data_model.md` — output tables and metric definitions
  - `line_insights_setup.md` — LINE opens/clicks limits and LINE OA Insights setup
  - `mail_report.md` — daily mail report; `dashboard.md` — dashboard build

## How the template works

- `td_engage_studio_analytics.dig`: `+setup` (CREATE TABLE IF NOT EXISTS) → `+email` / `+line` (delete rows whose **send date** is within `lookback_days`, re-insert) → `+unified` (rebuild `message_summary`, `send_cohort`, `daily`) → `+mail_report` (`td>` builds HTML fragments with `store_last_results`, `mail>` sends `templates/mail_daily_report.html`).
- Email `events.time` is the **send time**; opens/clicks arrive days–weeks later in the send-time partition. That is why each run rebuilds the last `lookback_days` (default 60) by send date.
- Message key: email `campaign_id` (Campaign) → `custom_event_id` (Journey/Activation); LINE `campaign_id`. Subjects are personalized, so never key on subject.
- Dashboard and mail read only `message_summary` / `send_cohort` / `daily` (+ `email_link_clicks`, `line_oa_daily`). `send_cohort` is additive, so filtered rates are correct.
- No `py>` in the WF. The dashboard is built outside the WF by `dashboard/build_dashboard.py`.
- Behavior changes are made by editing config and pushing. Don't suggest `-p` overrides — they don't override `_export` values on TD.

## Step 1. Locate or fetch the template

- Use `templates/project/` in this skill's folder. If it is missing (skill copied without templates), clone:
  `git clone --depth 1 https://github.com/tsukaharakazuki/td_tas_skill_extension.git .td_tas_src` → `.td_tas_src/td-engage-studio-analytics-builder/templates/project/`
- If the working directory already contains `td_engage_studio_analytics.dig`, the user opened an existing project — edit that instead.
- Copy into a new customer folder (don't overwrite an existing one), excluding the sample captures:
  `rsync -a --exclude docs/images <skill_dir>/templates/project/ ./<project_name>/`
- Read `README.md`, the dig, and `config/*.yml` first.

## Step 2. Discover the environment (read-only, before asking)

```bash
tdx status                                   # profile / site → console_url
tdx databases "delivery_email_*"
tdx tables "delivery_email_<domain>.*"        # events / error_events
tdx databases "delivery_line_*"
tdx describe delivery_line_<id>.<table>       # → log_format
```

Run the check queries in `docs/source_schema.md` on the last 30–60 days and note: event_type mix, test_mode values, is_bot_event share, Campaign vs Journey ratio (`campaign_id` NULL?), open/click lag percentiles, error_events presence.

**LINE: confirm every time whether it is actually being sent** — count rows in the last 30/90 days, excluding test_mode. A database with only test rows means "set up but not in use"; say so and ask.

If real columns differ from `source_schema.md`, adapt the SQL (and the matching `queries/setup/create_*.sql`, same column order) instead of forcing the config.

## Step 3. Interview (one message, show what you found)

1. Channels: email only / email + LINE (state the LINE row counts you found).
2. Output DB name and `table_prefix`; timezone (`tz`); exclude test sends (default yes).
3. LINE opens/clicks needed? Explain they are **not in the delivery log**. If needed, explain the options and limits in `line_insights_setup.md` (Message Deliveries = daily account-level counts; User Interaction Statistics needs request IDs and may not work for per-user Push). Ask who will register the Channel Access Token in Integration Hub.
4. Friendly message names (Journey `custom_event_id`s are UUIDs) → `message_names`.
5. Dashboard: needed? who sees it (subjects may contain names — mention `message_names`)?
6. Daily mail report: yes/no. If yes — recipients (to/cc/bcc), test recipient, send time, `subject_brand` / `title`, `account_label`, `dashboard_url`, send when there were no deliveries.
7. Error-notification recipients.

When the user has no preference: email on, LINE per discovery, `lookback_days: 60`, exclude test, mail report off until a test send is approved, schedule daily 08:00 JST.

## Step 4. Write the configs

- `common.yml`: `td.database` = `output_db`, `table_prefix`, `lookback_days`, `rebuild_all: true` for the first run, `exclude_test`, `tz`, `console_url`.
- `email.yml`: `database`, `error_events_enabled` only if the table exists.
- `line.yml`: `enabled`, `database`, `table`, `log_format` (`auto_log` if `delivered`/`line_request_id` exist; `event_log` if `event`/`error_code` exist), `insights_*`.
- `mail_report.yml`, `send_email_list.yml`, `test_email_list.yml`, `error_email_list.yml`. No single quotes in subject/title/label (embedded in SQL).
- Schedule: uncomment `schedule:` in the dig only after the first successful run.

## Step 5. Verify (read-only)

Render each SQL by hand (replace `${...}` with config values) and run it as `SELECT ... LIMIT` / aggregated counts with `tdx query`. Compare totals against your Step 2 profile (e.g. Send count for 30 days). Never run INSERT/DELETE/CREATE yourself — the WF does that.

## Step 6. Deploy and run

1. Create the output DB if missing (confirm first): `tdx db create <output_db>`.
2. New project: `tdx wf upload <project_dir>`; existing project with `tdx.json`: `tdx wf push --dry-run` then `tdx wf push`.
3. First run with `rebuild_all: true` and `mail_report.enabled: false`. `tdx wf run` writes tables — run `--dry-run`, explain, and wait for explicit approval. Then set `rebuild_all: false` and push.
4. Mail: run `send_test_mail.dig` to the test recipient only (dry-run first, confirm the recipient). After approval of the look and numbers, set `enabled: true`, real recipients, push, enable the schedule.
5. Check the `[settings]` and `[mail_report]` echo lines in the attempt log.

## Step 7. Dashboard

```bash
python3 dashboard/build_dashboard.py --db <output_db> --prefix <table_prefix> --out output/engage_studio_dashboard.html
```

Open it with `mcp__work__open_file`, compare with `docs/images/dashboard_overview.png`, check filters (channel / date / message / Bot) and a message detail. Publish (Apps Script / Drive) only when the user asks. Keep the TD template rules: `--tas-*` colors only, logo and "Prepared by Treasure Data" unchanged.

## Output format

Finish with:
1. Discovery table: channel / source table / rows (30d) / Campaign vs Journey / notes (test, bot share, doc differences)
2. Config summary and the edited files (open with `mcp__work__open_file`)
3. Deploy status — what was pushed/run vs. not yet (never report an unexecuted push, run, or mail as done)
4. Remaining manual steps (LINE token, output DB, schedule, recipients) and risks

## Example

**Input:** 「delivery_email_mail_example_com の配信結果を毎朝メールで報告したい。LINEもやってるかも」

**Output (abridged):**
- Discovery: email 30d Send 12,340 / 18 messages (Campaign 4, Journey 14), Open Bot=Likely 31%, no `error_events`; `delivery_line_abc.line_events` 30d 0 rows (test only on 2026-08-15) → 「LINEは現在配信されていないようです。集計対象に含めますか？」
- Configs: `email.yml` database set, `error_events_enabled: false`; `line.yml enabled: false`; `mail_report.yml enabled: false` until the test send is approved
- Next: upload → dry-run → first run (approval) → `send_test_mail.dig` to the requester → enable mail and schedule 08:00

## Edge cases

- Several sending domains → several `delivery_email_*` DBs: one project per domain with different `table_prefix` into the same `output_db`, or extend `recipients.sql` etc. with `UNION ALL`.
- Very large volumes: lower `lookback_days` (opens after the window are then not counted — state the trade-off) or run DELETE per day.
- `test_mode` all NULL in old data: treated as non-test.
- Opens without Delivery (open pixel before delivery event) are possible; rates use delivered as the denominator and can exceed 100% only in tiny samples.
- LINE `event_log` format has no user ID → unique recipients are NULL.
