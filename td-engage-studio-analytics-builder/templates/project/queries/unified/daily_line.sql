-- =====================================================================
-- 全チャネル: 日別 × メッセージ（LINE分）
-- 出力: ${table_prefix}daily に追加（channel = 'line'）
-- =====================================================================
WITH s AS (
  SELECT message_key, message_label
  FROM ${output_db}.${table_prefix}message_summary
  WHERE channel = 'line'
)

SELECT
  'line'                        AS channel,
  d.send_date                   AS date,
  d.message_key,
  COALESCE(MAX(s.message_label), d.message_key) AS message_label,
  COUNT(1)                      AS sent,
  SUM(d.is_delivered)           AS delivered,
  SUM(d.is_failed)              AS failed,
  CAST(NULL AS BIGINT)          AS complained,
  SUM(d.is_failed)              AS errors,
  CAST(NULL AS BIGINT)          AS opened,
  CAST(NULL AS BIGINT)          AS opened_human,
  CAST(NULL AS BIGINT)          AS clicked,
  CAST(NULL AS BIGINT)          AS clicked_human,
  TD_TIME_PARSE(d.send_date, '${tz}') AS time
FROM ${output_db}.${table_prefix}line_deliveries d
LEFT JOIN s ON s.message_key = d.message_key
GROUP BY d.send_date, d.message_key
