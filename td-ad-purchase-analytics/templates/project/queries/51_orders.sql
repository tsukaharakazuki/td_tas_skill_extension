-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: orders | TD Trino syntax unverified.
-- Contract: one row per order_id = latest snapshot (order_updated_time DESC, event_key DESC).
--   Orders without member_id are kept (QA). latest_conflict_variants > 1 means different identity/time/total/currency at the
--   same latest update time -> hard QA error. snapshot_variants > 1 (any field differs across snapshots) -> diagnostic.
WITH r AS (
  SELECT
    o.*,
    ROW_NUMBER() OVER (PARTITION BY o.order_id ORDER BY o.order_updated_time DESC, o.event_key DESC) AS rn,
    MAX(o.order_updated_time) OVER (PARTITION BY o.order_id) AS max_updated_time,
    JSON_FORMAT(CAST(ARRAY[o.order_total, o.currency] AS JSON)) AS amount_variant,
    JSON_FORMAT(CAST(ARRAY[CAST(o.order_time AS VARCHAR), o.member_id, o.td_client_id, o.order_total, o.currency] AS JSON)) AS full_variant
  FROM ${td.database}.${table_prefix}_order_raw_${session_unixtime}_${attempt_id} o
  WHERE o.order_id IS NOT NULL AND o.order_time IS NOT NULL
),
v AS (
  SELECT
    order_id,
    COUNT(*) AS snapshot_count,
    COUNT(DISTINCT CASE WHEN order_updated_time = max_updated_time THEN full_variant END) AS latest_conflict_variants,
    COUNT(DISTINCT full_variant) AS snapshot_variants
  FROM r
  GROUP BY order_id
)
SELECT
  r.order_id,
  r.order_time,
  r.order_updated_time,
  r.member_id,
  r.td_client_id,
  r.order_total,
  r.currency,
  r.event_key,
  r.source_system,
  v.snapshot_count,
  v.latest_conflict_variants,
  v.snapshot_variants,
  r.order_time AS time
FROM r
JOIN v ON v.order_id = r.order_id
WHERE r.rn = 1
