-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: event_sessions | TD Trino syntax unverified.
-- Contract: web events with td_client_id, plus raw_session_token (internal grouping key only, never a public/permanent id).
--   window: TD_SESSIONIZE_WINDOW result materialized exactly once here; sdk: the SDK session id.
--   NULL token rows stay here and are excluded by 20_sessions (counted by QA from web).
WITH w AS (
  SELECT
    e.*,
    TD_SESSIONIZE_WINDOW(e.event_time, ${session_timeout_seconds})
      OVER (PARTITION BY e.td_client_id ORDER BY e.event_time) AS window_session
  FROM ${td.database}.${table_prefix}_web_${session_unixtime}_${attempt_id} e
  WHERE e.td_client_id IS NOT NULL
)
SELECT
  event_time, td_client_id, member_id, sdk_session_id, url, referrer,
  source, medium, campaign, content, term,
  is_login, is_purchase, order_id, order_total, currency, event_key, is_entry, inflow_kind,
  CASE WHEN '${session_mode}' = 'sdk' THEN sdk_session_id ELSE window_session END AS raw_session_token,
  time
FROM w
