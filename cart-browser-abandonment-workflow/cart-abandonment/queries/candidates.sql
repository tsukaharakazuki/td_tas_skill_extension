WITH bounds AS (
  SELECT
    CASE WHEN '${config.window.kind}' = 'overnight' THEN
      TD_TIME_PARSE(
        CAST(DATE_ADD('day', -1, CAST(TD_TIME_FORMAT(${session_unixtime}, 'yyyy-MM-dd', '${config.timezone}') AS DATE)) AS VARCHAR)
        || ' ${config.window.overnight_start}', '${config.timezone}')
    ELSE ${session_unixtime} - ${config.window.max_age_seconds} END AS window_start,
    CASE WHEN '${config.window.kind}' = 'overnight' THEN
      LEAST(TD_TIME_PARSE(TD_TIME_FORMAT(${session_unixtime}, 'yyyy-MM-dd', '${config.timezone}')
            || ' ${config.window.overnight_end}', '${config.timezone}'),
            ${session_unixtime} - ${config.window.inactivity_seconds})
    ELSE ${session_unixtime} - ${config.window.inactivity_seconds} END AS window_end
), sessions AS (
  SELECT member_id, session_no, MIN(time) AS session_start, MAX(time) AS session_end
  FROM ${config.output.database}.${config.output.prefix}_events
  GROUP BY member_id, session_no
), ranked_sessions AS (
  -- Choose latest session BEFORE testing eligibility: never resurrect an older one.
  SELECT *, ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY session_end DESC, session_no DESC) AS rn
  FROM sessions
), latest AS (
  SELECT s.* FROM ranked_sessions s CROSS JOIN bounds b
  WHERE s.rn = 1 AND s.session_end >= b.window_start AND s.session_end < b.window_end
), cart_actions AS (
  SELECT DISTINCT e.member_id, e.session_no, e.event_id, e.time, e.event_type
  FROM ${config.output.database}.${config.output.prefix}_events e
  JOIN latest s ON e.member_id = s.member_id AND e.session_no = s.session_no
  WHERE e.event_type IN ('cart_item', 'cart_clear')
), cart_ranked AS (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY member_id ORDER BY time DESC,
      CASE WHEN event_type = 'cart_clear' THEN 1 ELSE 0 END DESC, event_id DESC
  ) AS rn
  FROM cart_actions
), browser_ranked AS (
  SELECT e.*, ROW_NUMBER() OVER (PARTITION BY e.member_id ORDER BY e.time DESC, e.event_id DESC, e.product_id) AS rn
  FROM ${config.output.database}.${config.output.prefix}_events e
  JOIN latest s ON e.member_id = s.member_id AND e.session_no = s.session_no
  WHERE e.event_type = 'product_view'
), signals AS (
  SELECT member_id, session_no, event_id, time AS signal_time, 'cart' AS kind
  FROM cart_ranked WHERE rn = 1 AND event_type = 'cart_item' AND '${config.mode}' IN ('cart', 'both')
  UNION ALL
  SELECT member_id, session_no, event_id, time AS signal_time, 'browser' AS kind
  FROM browser_ranked WHERE rn = 1 AND '${config.mode}' IN ('browser', 'both')
)
SELECT c.member_id, c.session_no, c.event_id, c.signal_time, c.kind
FROM signals c
WHERE NOT EXISTS (
  SELECT 1 FROM ${config.output.database}.${config.output.prefix}_events p
  WHERE p.member_id = c.member_id AND p.event_type = 'purchase'
    AND (p.session_no = c.session_no OR p.time >= c.signal_time
         OR p.time >= ${session_unixtime} - ${config.suppression.purchase_seconds})
)
AND NOT EXISTS (
  SELECT 1 FROM ${config.sources.orders} o
  WHERE o.time >= ${session_unixtime} - ${config.scan.lookback_seconds}
    AND o.time < ${session_unixtime} AND o.member_id = c.member_id
    AND COALESCE(o.cancelled, FALSE) = FALSE
    AND (o.time >= c.signal_time OR o.time >= ${session_unixtime} - ${config.suppression.purchase_seconds})
)
AND (c.kind = 'cart' OR NOT EXISTS (
  -- Shared member-level, cross-device suppression. No cart send table/history needed.
  SELECT 1 FROM ${config.output.database}.${config.output.prefix}_events x
  WHERE x.member_id = c.member_id AND x.event_type IN ('cart_item', 'cart_clear')
    AND (x.session_no = c.session_no OR x.time >= c.signal_time
         OR x.time >= ${session_unixtime} - ${config.suppression.cart_seconds})
))
