-- =====================================================================
-- 全チャネル: 日別 × メッセージ（メール分）
-- 出力: ${table_prefix}daily に追加（channel = 'email'）
-- ---------------------------------------------------------------------
-- date はイベントが起きた日。opened / clicked はその日に開封・クリックがあった通数
-- （同じ通が別の日にも開封されると、それぞれの日に数えます）
-- =====================================================================
WITH ev AS (
  SELECT
    message_key,
    event_date AS date,
    SUM(IF(event_type = 'Send',      recipients, 0))       AS sent,
    SUM(IF(event_type = 'Delivery',  recipients, 0))       AS delivered,
    SUM(IF(event_type = 'Bounce',    recipients, 0))       AS failed,
    SUM(IF(event_type = 'Complaint', recipients, 0))       AS complained,
    SUM(IF(event_type = 'Open',      recipients, 0))       AS opened,
    SUM(IF(event_type = 'Open',      recipients_human, 0)) AS opened_human,
    SUM(IF(event_type = 'Click',     recipients, 0))       AS clicked,
    SUM(IF(event_type = 'Click',     recipients_human, 0)) AS clicked_human
  FROM ${output_db}.${table_prefix}email_events_daily
  GROUP BY 1, 2
),
er AS (
  SELECT message_key, error_date AS date, SUM(errors) AS errors
  FROM ${output_db}.${table_prefix}email_errors_daily
  GROUP BY 1, 2
),
k AS (
  SELECT message_key, date FROM ev
  UNION
  SELECT message_key, date FROM er
),
s AS (
  SELECT message_key, message_label
  FROM ${output_db}.${table_prefix}message_summary
  WHERE channel = 'email'
)

SELECT
  'email'                       AS channel,
  k.date,
  k.message_key,
  COALESCE(s.message_label, k.message_key) AS message_label,
  COALESCE(ev.sent, 0)          AS sent,
  COALESCE(ev.delivered, 0)     AS delivered,
  COALESCE(ev.failed, 0)        AS failed,
  COALESCE(ev.complained, 0)    AS complained,
  COALESCE(er.errors, 0)        AS errors,
  COALESCE(ev.opened, 0)        AS opened,
  COALESCE(ev.opened_human, 0)  AS opened_human,
  COALESCE(ev.clicked, 0)       AS clicked,
  COALESCE(ev.clicked_human, 0) AS clicked_human,
  TD_TIME_PARSE(k.date, '${tz}') AS time
FROM k
LEFT JOIN ev ON ev.message_key = k.message_key AND ev.date = k.date
LEFT JOIN er ON er.message_key = k.message_key AND er.date = k.date
LEFT JOIN s  ON s.message_key  = k.message_key
