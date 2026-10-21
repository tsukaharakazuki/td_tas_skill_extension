-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: sessions | TD Trino syntax unverified.
-- Contract: one row per (td_client_id, raw_session_token); events join back on that pair.
--   session_key: window -> cookie:session_start, sdk -> cookie:sdk_session_id (stable across reruns).
--   session_member_id = MAX(member_id) (deliberate string ordering; conflicts kept as member_id_count > 1, not an error).
--   first_login_time = first actual is_login event of the selected member in the session (never back-filled).
--   landing_* = canonical fields at min (event_time, event_key).
WITH e AS (
  SELECT
    es.*,
    MAX(es.member_id) OVER (PARTITION BY es.td_client_id, es.raw_session_token) AS selected_member_id
  FROM ${td.database}.${table_prefix}_event_sessions_${session_unixtime}_${attempt_id} es
  WHERE es.raw_session_token IS NOT NULL
),
g AS (
  SELECT
    td_client_id,
    raw_session_token,
    MIN(event_time) AS session_start,
    MAX(event_time) AS session_end,
    COUNT(*) AS event_count,
    MAX(member_id) AS session_member_id,
    COUNT(DISTINCT member_id) AS member_id_count,
    MIN(CASE WHEN is_login = 1 AND member_id = selected_member_id THEN event_time END) AS first_login_time,
    MIN_BY(event_key,   ROW(event_time, event_key)) AS landing_event_key,
    MIN_BY(source,      ROW(event_time, event_key)) AS landing_source,
    MIN_BY(medium,      ROW(event_time, event_key)) AS landing_medium,
    MIN_BY(campaign,    ROW(event_time, event_key)) AS landing_campaign,
    MIN_BY(content,     ROW(event_time, event_key)) AS landing_content,
    MIN_BY(term,        ROW(event_time, event_key)) AS landing_term,
    MIN_BY(inflow_kind, ROW(event_time, event_key)) AS landing_inflow_kind,
    MIN_BY(url,         ROW(event_time, event_key)) AS landing_url
  FROM e
  GROUP BY td_client_id, raw_session_token
),
k AS (
  SELECT
    g.*,
    CASE WHEN '${session_mode}' = 'sdk'
      THEN td_client_id || ':' || raw_session_token
      ELSE td_client_id || ':' || CAST(session_start AS VARCHAR)
    END AS session_key
  FROM g
)
SELECT
  td_client_id,
  raw_session_token,
  session_key,
  ROW_NUMBER() OVER (PARTITION BY td_client_id ORDER BY session_start, session_key) AS session_number,
  session_start,
  session_end,
  event_count,
  session_member_id,
  member_id_count,
  first_login_time,
  landing_event_key,
  landing_source, landing_medium, landing_campaign, landing_content, landing_term,
  landing_inflow_kind,
  landing_url,
  session_start AS time
FROM k
