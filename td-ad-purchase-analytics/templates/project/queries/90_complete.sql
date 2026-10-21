-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: complete | TD Trino syntax unverified.
-- Contract: exactly one row describing this attempt's snapshot, written only after QA passed
--   (defensive filter: zero rows if the QA table reports hard errors). No secrets, no raw ids/URLs.
--   All marts of this snapshot are ${td.database}.${table_prefix}_<mart>_<table_suffix>.
SELECT
  '${attempt_id}' AS attempt_id,
  '${session_unixtime}_${attempt_id}' AS run_id,
  '${session_unixtime}_${attempt_id}' AS table_suffix,
  ${session_unixtime} AS session_unixtime,
  ${session_unixtime} AS cutoff_unixtime,
  '${config_sha256}' AS config_sha256,
  '${td.database}' AS output_database,
  '${table_prefix}' AS table_prefix,
  '${web_table}' AS web_table,
  '${session_mode}' AS session_mode,
  ${session_timeout_seconds} AS session_timeout_seconds,
  ${lookback_days} AS lookback_days,
  '${report_start}' AS report_start,
  '${report_end}' AS report_end,
  '${report_timezone}' AS report_timezone,
  '${currency}' AS currency,
  '${ad_costs_enabled}' AS ad_costs_enabled,
  'full_retained_history' AS refresh_strategy,
  q.web_rows AS input_rows,
  q.web_min_event_time AS input_min_event_time,
  q.web_max_event_time AS input_max_event_time,
  q.web_cookies AS input_cookies,
  q.min_acquisition_time,
  q.sessions,
  q.acquisition_rows AS acquired_cookies_all_history,
  q.cohort_cookies,
  q.orders,
  q.owned_orders,
  q.unmatched_orders,
  q.cohort_rows,
  q.inflow_rows,
  q.lookback_rows,
  q.cost_grain_rows,
  q.warning_count,
  q.warnings,
  q.hard_error_count,
  ${session_unixtime} AS time
FROM ${td.database}.${table_prefix}_qa_${session_unixtime}_${attempt_id} q
WHERE q.hard_error_count = 0
