-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: order_raw (purchase_mode = web) | TD Trino syntax unverified.
-- Contract: canonical order snapshots from web purchase events with a non-null order_id
--   (purchase signals without order_id are counted by QA, never used as orders).
--   Re-fires are snapshots, not new purchases. Freeze transaction time at the earliest purchase signal;
--   51_orders selects the latest snapshot's amount/identity without shifting purchase time after a later login.
SELECT
  order_id,
  MIN(event_time) OVER (PARTITION BY order_id) AS order_time,
  event_time AS order_updated_time,
  member_id,
  td_client_id,
  order_total,
  currency,
  event_key,
  'web' AS source_system,
  event_time AS time
FROM ${td.database}.${table_prefix}_web_${session_unixtime}_${attempt_id}
WHERE is_purchase = 1
  AND order_id IS NOT NULL
