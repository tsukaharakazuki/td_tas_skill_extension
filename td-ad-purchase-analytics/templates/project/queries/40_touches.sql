-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: touches | TD Trino syntax unverified.
-- Contract (occurrence level; two modes in one table; never sum across modes):
--   touch_mode='landing'        : one row per session (first event); additivity='exclusive_within_mode'.
--   touch_mode='session_inflow' : EVERY occurrence among landing + explicit external/UTM entries.
--                                 Only duplicate event keys collapse here; deduplicate cookie/source in 71_inflow.
--                                 Keep later same-source occurrences for lookback. First-session occurrences are all new.
--   session_member_id = session MAX member (retrospective: also labels events before the in-session login).
WITH s AS (
  SELECT * FROM ${td.database}.${table_prefix}_sessions_${session_unixtime}_${attempt_id}
),
occ AS (
  SELECT
    s.td_client_id, s.session_key, s.session_number, s.session_start, s.session_member_id, s.first_login_time,
    e.event_time, e.event_key, e.source, e.medium, e.campaign, e.content, e.term, e.inflow_kind,
    CASE WHEN e.event_key = s.landing_event_key THEN 1 ELSE 0 END AS is_landing,
    ROW_NUMBER() OVER (
      PARTITION BY s.session_key, e.event_key
      ORDER BY e.event_time, e.event_key
    ) AS rn
  FROM ${td.database}.${table_prefix}_event_sessions_${session_unixtime}_${attempt_id} e
  JOIN s
    ON s.td_client_id = e.td_client_id
   AND s.raw_session_token = e.raw_session_token
  WHERE e.is_entry = 1 OR e.event_key = s.landing_event_key
)
SELECT
  'landing' AS touch_mode,
  'exclusive_within_mode' AS additivity,
  td_client_id, session_key, session_number,
  CASE WHEN session_number = 1 THEN 1 ELSE 0 END AS is_new_session,
  session_start, session_member_id, first_login_time AS session_first_login_time,
  session_start AS touch_time,
  landing_event_key AS event_key,
  landing_source AS source, landing_medium AS medium, landing_campaign AS campaign,
  landing_content AS content, landing_term AS term, landing_inflow_kind AS inflow_kind,
  1 AS is_landing,
  session_start AS time
FROM s
UNION ALL
SELECT
  'session_inflow' AS touch_mode,
  'nonadditive' AS additivity,
  td_client_id, session_key, session_number,
  CASE WHEN session_number = 1 THEN 1 ELSE 0 END AS is_new_session,
  session_start, session_member_id, first_login_time AS session_first_login_time,
  event_time AS touch_time,
  event_key,
  source, medium, campaign, content, term, inflow_kind,
  is_landing,
  event_time AS time
FROM occ
WHERE rn = 1
