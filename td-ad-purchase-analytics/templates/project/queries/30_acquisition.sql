-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: acquisition | TD Trino syntax unverified.
-- Contract: one row per cookie = its first retained session (session_number = 1), built over full history.
--   in_cohort = report_start <= acquisition_time < report_end (report_timezone), flagged only after full history.
--   first_login_time = first member observation of the cookie up to cutoff (observed state, not necessarily a login event).
WITH fl AS (
  SELECT
    td_client_id,
    MIN(observed_time) AS first_login_time,
    MIN_BY(member_id, ROW(observed_time, event_key)) AS first_login_member_id
  FROM ${td.database}.${table_prefix}_members_${session_unixtime}_${attempt_id}
  GROUP BY td_client_id
)
SELECT
  s.td_client_id,
  s.session_key AS first_session_key,
  s.session_start AS acquisition_time,
  FORMAT_DATETIME(FROM_UNIXTIME(s.session_start, '${report_timezone}'), 'yyyy-MM-dd') AS acquisition_date,
  s.landing_source AS source,
  s.landing_medium AS medium,
  s.landing_campaign AS campaign,
  s.landing_content AS content,
  s.landing_term AS term,
  s.landing_inflow_kind,
  fl.first_login_time,
  fl.first_login_member_id,
  CASE WHEN s.session_start >= TD_TIME_PARSE('${report_start}', '${report_timezone}')
        AND s.session_start <  TD_TIME_PARSE('${report_end}', '${report_timezone}')
       THEN 1 ELSE 0 END AS in_cohort,
  s.session_start AS time
FROM ${td.database}.${table_prefix}_sessions_${session_unixtime}_${attempt_id} s
LEFT JOIN fl ON fl.td_client_id = s.td_client_id
WHERE s.session_number = 1
