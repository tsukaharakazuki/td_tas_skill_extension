-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: members | TD Trino syntax unverified.
-- Contract: raw is_login events whose member_id equals the session's selected (MAX) member, at their actual event time.
SELECT
  e.td_client_id,
  s.session_key,
  s.raw_session_token,
  s.session_number,
  e.member_id,
  e.event_time AS observed_time,
  e.event_key,
  e.event_time AS time
FROM ${td.database}.${table_prefix}_event_sessions_${session_unixtime}_${attempt_id} e
JOIN ${td.database}.${table_prefix}_sessions_${session_unixtime}_${attempt_id} s
  ON s.td_client_id = e.td_client_id
 AND s.raw_session_token = e.raw_session_token
WHERE e.is_login = 1
  AND e.member_id = s.session_member_id
