-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: order_raw (purchase_mode = separate) | ADAPTER | TD Trino syntax unverified.
-- Active only when purchase_mode = separate: the validator must then fail on any REPLACE_ME token.
-- When purchase_mode = web this file is unused and may stay unresolved.
-- Contract: order-header grain snapshots with order_id, order_time (transaction time, epoch s),
--   order_updated_time (snapshot/update time, epoch s), member_id, td_client_id (nullable, informational only),
--   order_total DECIMAL(18,2) as VARCHAR, currency, event_key. Status filter and line->header grain are manual:
--   never SUM a repeated order-level total across line rows.
WITH src AS (
  SELECT
    NULLIF(TRIM(CAST(REPLACE_ME_order_id_expr AS VARCHAR)), '') AS order_id,
    CAST(REPLACE_ME_order_time_epoch_expr AS BIGINT) AS order_time,
    CAST(REPLACE_ME_order_updated_time_epoch_expr AS BIGINT) AS order_updated_time_raw,
    NULLIF(TRIM(CAST(REPLACE_ME_member_id_expr AS VARCHAR)), '') AS member_id,
    NULLIF(TRIM(CAST(REPLACE_ME_td_client_id_expr_or_null AS VARCHAR)), '') AS td_client_id,
    TRY_CAST(REPLACE_ME_order_total_expr AS DECIMAL(18, 2)) AS order_total,
    NULLIF(UPPER(TRIM(CAST(REPLACE_ME_currency_expr AS VARCHAR))), '') AS currency,
    NULLIF(TRIM(CAST(REPLACE_ME_native_row_id_expr_or_null AS VARCHAR)), '') AS native_row_id
  FROM REPLACE_ME_order_database.REPLACE_ME_order_table
  WHERE REPLACE_ME_status_and_grain_filter_expr
    -- add a partition cutoff if the table is time-partitioned, e.g. AND TD_TIME_RANGE(time, NULL, ${session_unixtime})
),
n AS (
  SELECT
    order_id,
    order_time,
    COALESCE(order_updated_time_raw, order_time) AS order_updated_time,
    member_id,
    td_client_id,
    order_total,
    currency,
    native_row_id
  FROM src
  -- Keep invalid mandatory keys/times visible to QA rather than silently dropping them.
  WHERE (order_time IS NULL OR order_time < ${session_unixtime})
    AND (COALESCE(order_updated_time_raw, order_time) IS NULL
         OR COALESCE(order_updated_time_raw, order_time) < ${session_unixtime})
)
SELECT
  order_id,
  order_time,
  order_updated_time,
  member_id,
  td_client_id,
  CAST(order_total AS VARCHAR) AS order_total,
  currency,
  COALESCE(
    'n:' || native_row_id,
    'h:' || LOWER(TO_HEX(SHA256(TO_UTF8(JSON_FORMAT(CAST(ARRAY[
      order_id, CAST(order_time AS VARCHAR), CAST(order_updated_time AS VARCHAR),
      member_id, td_client_id, CAST(order_total AS VARCHAR), currency
    ] AS JSON))))))
  ) AS event_key,
  'separate' AS source_system,
  COALESCE(order_time, ${session_unixtime} - 1) AS time
FROM n
