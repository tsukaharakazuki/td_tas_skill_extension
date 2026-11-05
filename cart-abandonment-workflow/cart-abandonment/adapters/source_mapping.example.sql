-- GUIDED EXAMPLE ONLY; not referenced by .dig. These raw_data tables are a
-- hypothetical row-based source contract, NOT asserted to exist in any account.
-- Replace source columns/expressions after the interview. Materialize each SELECT
-- separately into the corresponding canonical table. Do not paste raw names into
-- queries/*.sql, which operate solely on the documented canonical contract.
-- 1) events: one row per product in a COMPLETE cart snapshot. A delta-only
-- add_to_cart stream must be reconstructed upstream; relabeling it is incorrect.
SELECT
  CAST(event_epoch_seconds AS BIGINT) AS time,
  CAST(event_key AS VARCHAR) AS event_id,
  NULLIF(TRIM(CAST(device_key AS VARCHAR)), '') AS device_id,
  NULLIF(TRIM(CAST(account_key AS VARCHAR)), '') AS member_id,
  CASE action
    WHEN 'product_detail' THEN 'product_view'
    WHEN 'cart_snapshot_item' THEN 'cart_item'
    WHEN 'empty_cart_snapshot' THEN 'cart_clear'
    WHEN 'completed_order' THEN 'purchase'
    ELSE 'activity' END AS event_type,
  CAST(sku AS VARCHAR) AS product_id, CAST(units AS BIGINT) AS quantity,
  CAST(position AS BIGINT) AS item_position, CAST(product_name AS VARCHAR) AS item_name,
  CAST(product_url AS VARCHAR) AS item_url, CAST(product_image_url AS VARCHAR) AS image_url,
  CAST(product_brand AS VARCHAR) AS brand, CAST(unit_price AS DOUBLE) AS price,
  CAST(regular_price AS DOUBLE) AS original_price
FROM raw_data.web_event_rows
WHERE time >= ${session_unixtime} - ${config.scan.lookback_seconds} - ${config.window.expected_latency_seconds}
  AND time < ${session_unixtime}
  AND event_epoch_seconds >= ${session_unixtime} - ${config.scan.lookback_seconds}
  AND event_epoch_seconds < ${session_unixtime}
  AND is_bot = FALSE;

-- 2) recipients: keep revocations/deletions and stable row_id tie-breakers.
-- DO NOT filter to opted-in rows here: latest-row consent is decided downstream.
SELECT time, CAST(change_id AS VARCHAR) AS row_id,
  CAST(account_key AS VARCHAR) AS member_id, LOWER(TRIM(email_address)) AS email,
  CASE WHEN email_status = 'subscribed' THEN TRUE ELSE FALSE END AS consent,
  CASE WHEN blocked = FALSE THEN FALSE ELSE TRUE END AS suppressed,
  CAST(changed_at_epoch_seconds AS BIGINT) AS updated_at
FROM raw_data.contact_changes;

-- 3) orders: include all known member-linked channels/devices; retain cancellations.
-- An empty order table is acceptable only if complete web purchase tracking has
-- been verified and this reduced protection has been explicitly accepted.
SELECT CAST(ordered_at_epoch_seconds AS BIGINT) AS time,
  CAST(order_key AS VARCHAR) AS order_id, CAST(account_key AS VARCHAR) AS member_id,
  CAST(sku AS VARCHAR) AS product_id, CAST(is_cancelled AS BOOLEAN) AS cancelled
FROM raw_data.order_lines;
