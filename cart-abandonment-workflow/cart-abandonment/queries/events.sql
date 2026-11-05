-- Canonical business-event time is Unix SECONDS, also the TD time partition.
-- Reject missing devices; never group all anonymous visitors under one sentinel.
WITH identity_ranked AS (
  SELECT device_id, member_id,
         ROW_NUMBER() OVER (PARTITION BY device_id ORDER BY updated_at DESC, row_id DESC) AS rn
  FROM ${config.sources.identities}
  WHERE updated_at <= ${session_unixtime}
), identity_evidence AS (
  SELECT device_id, NULLIF(TRIM(member_id), '') AS member_id
  FROM ${config.sources.identities} WHERE updated_at <= ${session_unixtime}
  UNION
  SELECT device_id, NULLIF(TRIM(member_id), '') AS member_id
  FROM ${config.sources.events}
  WHERE time >= ${session_unixtime} - ${config.scan.lookback_seconds} AND time < ${session_unixtime}
), unsafe_devices AS (
  SELECT device_id FROM identity_evidence
  WHERE NULLIF(TRIM(device_id), '') IS NOT NULL AND member_id IS NOT NULL
  GROUP BY device_id HAVING COUNT(DISTINCT member_id) > 1
), unsafe_members AS (
  -- Fail closed for ALL members linked to a known shared device, across devices.
  SELECT DISTINCT e.member_id FROM identity_evidence e
  JOIN unsafe_devices d ON e.device_id = d.device_id WHERE e.member_id IS NOT NULL
), identity_unambiguous AS (
  SELECT device_id FROM identity_evidence
  WHERE member_id IS NOT NULL GROUP BY device_id HAVING COUNT(DISTINCT member_id) = 1
), identity_latest AS (
  SELECT i.device_id, NULLIF(TRIM(i.member_id), '') AS member_id
  FROM identity_ranked i JOIN identity_unambiguous u ON i.device_id = u.device_id
  WHERE i.rn = 1
), resolved AS (
  SELECT e.time, e.event_id, e.device_id,
         COALESCE(NULLIF(TRIM(e.member_id), ''), i.member_id) AS member_id,
         e.event_type, e.product_id, e.quantity, e.item_position,
         e.item_name, e.item_url, e.image_url, e.brand, e.price, e.original_price,
         ROW_NUMBER() OVER (
           PARTITION BY e.event_id, COALESCE(e.product_id, '')
           ORDER BY e.time DESC, e.device_id
         ) AS duplicate_row
  FROM ${config.sources.events} e
  LEFT JOIN identity_latest i ON e.device_id = i.device_id
  WHERE e.time >= ${session_unixtime} - ${config.scan.lookback_seconds}
    AND e.time < ${session_unixtime}
    AND NULLIF(TRIM(e.device_id), '') IS NOT NULL
    AND NULLIF(TRIM(e.event_id), '') IS NOT NULL
), clean AS (
  SELECT * FROM resolved r WHERE duplicate_row = 1 AND member_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM unsafe_members u WHERE u.member_id = r.member_id)
), actions AS (
  SELECT DISTINCT member_id, event_id, time FROM clean
), previous_action AS (
  SELECT *, LAG(time) OVER (PARTITION BY member_id ORDER BY time, event_id) AS previous_time
  FROM actions
), numbered AS (
  SELECT *, SUM(CASE WHEN previous_time IS NULL
                          OR time - previous_time >= ${config.window.session_timeout_seconds}
                    THEN 1 ELSE 0 END)
            OVER (PARTITION BY member_id ORDER BY time, event_id ROWS UNBOUNDED PRECEDING) AS session_no
  FROM previous_action
)
SELECT c.time, c.event_id, c.device_id, c.member_id, c.event_type,
       c.product_id, c.quantity, c.item_position, c.item_name, c.item_url,
       c.image_url, c.brand, c.price, c.original_price, n.session_no
FROM clean c JOIN numbered n
  ON c.member_id = n.member_id AND c.event_id = n.event_id AND c.time = n.time
