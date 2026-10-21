-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: lookback | TD Trino syntax unverified.
-- Contract: separate last-touch model, one row per order (no-touch and unowned orders preserved via LEFT JOIN).
--   Candidates: touch_mode='session_inflow' occurrences with
--     order_time - lookback_days*86400 <= touch_time < order_time,
--     session_member_id = owner_member_id (session MAX, retrospective label),
--     and an actual selected-member observation in that session before the order.
--   Last touch: touch_time DESC, session_key DESC, event_key DESC. Never add to cohort first-touch sales.
WITH oc AS (
  SELECT * FROM ${td.database}.${table_prefix}_order_credit_${session_unixtime}_${attempt_id}
),
t AS (
  SELECT *
  FROM ${td.database}.${table_prefix}_touches_${session_unixtime}_${attempt_id}
  WHERE touch_mode = 'session_inflow'
    AND session_member_id IS NOT NULL
),
cand AS (
  SELECT
    oc.order_id,
    t.td_client_id, t.session_key, t.touch_time, t.event_key,
    t.source, t.medium, t.campaign, t.content, t.term, t.inflow_kind,
    ROW_NUMBER() OVER (PARTITION BY oc.order_id ORDER BY t.touch_time DESC, t.session_key DESC, t.event_key DESC) AS rn,
    COUNT(*) OVER (PARTITION BY oc.order_id) AS candidate_count
  FROM oc
  JOIN t
    ON t.session_member_id = oc.owner_member_id
   AND t.touch_time >= oc.order_time - ${lookback_days} * 86400
   AND t.touch_time < oc.order_time
   AND t.session_first_login_time < oc.order_time
  WHERE oc.is_owned = 1
)
SELECT
  oc.order_id,
  oc.order_time,
  oc.order_total,
  oc.currency,
  oc.is_owned,
  oc.owner_td_client_id,
  oc.owner_member_id,
  'last_touch_session_inflow' AS attribution_model,
  ${lookback_days} AS lookback_days,
  'session_max_member_retrospective' AS touch_member_basis,
  CASE WHEN c.order_id IS NOT NULL THEN 1 ELSE 0 END AS has_touch,
  c.td_client_id AS touch_td_client_id,
  c.session_key AS touch_session_key,
  c.touch_time,
  c.event_key AS touch_event_key,
  c.source, c.medium, c.campaign, c.content, c.term,
  c.inflow_kind AS touch_inflow_kind,
  COALESCE(c.candidate_count, 0) AS candidate_touch_count,
  oc.order_time AS time
FROM oc
LEFT JOIN cand c
  ON c.order_id = oc.order_id
 AND c.rn = 1
