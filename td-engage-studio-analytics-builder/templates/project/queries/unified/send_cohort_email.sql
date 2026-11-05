-- =====================================================================
-- 全チャネル: 送信日 × メッセージ（メール分）
-- 出力: ${table_prefix}send_cohort に追加（channel = 'email'）
-- 指標の定義は message_summary_email.sql と同じ（送信日で分けただけ）
-- =====================================================================
WITH s AS (
  SELECT message_key, message_label
  FROM ${output_db}.${table_prefix}message_summary
  WHERE channel = 'email'
)

SELECT
  'email'                       AS channel,
  r.send_date,
  r.message_key,
  COALESCE(MAX(s.message_label), r.message_key) AS message_label,
  SUM(r.is_sent)                AS sent,
  SUM(r.is_delivered)           AS delivered,
  SUM(r.is_bounced)             AS failed,
  SUM(r.is_hard_bounced)        AS hard_bounced,
  SUM(r.is_complained)          AS complained,
  SUM(r.is_opened)              AS opened,
  SUM(r.is_opened_human)        AS opened_human,
  SUM(r.is_clicked)             AS clicked,
  SUM(r.is_clicked_human)       AS clicked_human,
  COUNT(DISTINCT r.to_address)  AS unique_recipients,
  TD_TIME_PARSE(r.send_date, '${tz}') AS time
FROM ${output_db}.${table_prefix}email_recipients r
LEFT JOIN s ON s.message_key = r.message_key
GROUP BY r.send_date, r.message_key
