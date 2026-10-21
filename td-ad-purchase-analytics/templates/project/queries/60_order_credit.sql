-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: order_credit | TD Trino syntax unverified.
-- Contract: one row per order (unmatched orders preserved). Owner = latest prior member observation, chosen over the
--   full cookie universe (before any cohort filter):
--     web      : same cookie AND observed_time < order_time AND (order.member_id IS NULL OR member equal)
--     separate : member equal AND observed_time < order_time (order td_client_id is ignored)
--   Tie-break: observed_time DESC, cookie ASC, event_key ASC.
WITH o AS (
  SELECT * FROM ${td.database}.${table_prefix}_orders_${session_unixtime}_${attempt_id}
),
m AS (
  SELECT td_client_id, member_id, observed_time, event_key
  FROM ${td.database}.${table_prefix}_members_${session_unixtime}_${attempt_id}
),
cand AS (
  SELECT o.order_id, m.td_client_id AS cookie, m.member_id, m.observed_time, m.event_key
  FROM o
  JOIN m
    ON m.td_client_id = o.td_client_id
   AND m.observed_time < o.order_time
  WHERE o.source_system = 'web'
    AND (o.member_id IS NULL OR m.member_id = o.member_id)
  UNION ALL
  SELECT o.order_id, m.td_client_id AS cookie, m.member_id, m.observed_time, m.event_key
  FROM o
  JOIN m
    ON m.member_id = o.member_id
   AND m.observed_time < o.order_time
  WHERE o.source_system = 'separate'
),
ranked AS (
  SELECT
    cand.*,
    ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY observed_time DESC, cookie ASC, event_key ASC) AS rn,
    COUNT(*) OVER (PARTITION BY order_id) AS candidate_count
  FROM cand
)
SELECT
  o.order_id,
  o.order_time,
  o.order_updated_time,
  o.member_id AS order_member_id,
  o.td_client_id AS order_td_client_id,
  o.order_total,
  o.currency,
  o.source_system,
  b.cookie AS owner_td_client_id,
  b.member_id AS owner_member_id,
  b.observed_time AS member_observed_time,
  CASE
    WHEN b.order_id IS NOT NULL AND o.source_system = 'web' THEN 'web_same_cookie_prior_member_observation'
    WHEN b.order_id IS NOT NULL THEN 'separate_member_prior_observation'
    WHEN o.source_system = 'web' AND o.td_client_id IS NULL THEN 'unmatched_cookie_missing'
    WHEN o.source_system = 'separate' AND o.member_id IS NULL THEN 'unmatched_member_missing'
    ELSE 'unmatched_no_prior_member_observation'
  END AS attribution_reason,
  COALESCE(b.candidate_count, 0) AS owner_candidate_count,
  CASE WHEN b.order_id IS NOT NULL THEN 1 ELSE 0 END AS is_owned,
  o.order_time AS time
FROM o
LEFT JOIN ranked b
  ON b.order_id = o.order_id
 AND b.rn = 1
