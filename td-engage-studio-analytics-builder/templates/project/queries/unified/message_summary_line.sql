-- =====================================================================
-- 全チャネル: メッセージ単位サマリー（LINE分）
-- 出力: ${table_prefix}message_summary に追加（channel = 'line'）
-- ---------------------------------------------------------------------
--   sent      : 送信リクエスト数（リトライはまとめて1）
--   delivered : LINE API が受け付けた数（2xx / delivered = true）
--   failed    : 最終的に失敗した数
--   opened / clicked : 配信ログにないため NULL（LINE の仕様）
-- =====================================================================
WITH d AS (
  SELECT
    message_key,
    MAX(campaign_name)                AS campaign_name,
    MAX(campaign_model)               AS campaign_model,
    MAX(campaign_id)                  AS campaign_id,
    MAX(line_channel_name)            AS sender,
    MIN(send_date)                    AS first_send_date,
    MAX(send_date)                    AS last_send_date,
    COUNT(DISTINCT send_date)         AS send_days,
    COUNT(1)                          AS sent,
    SUM(is_delivered)                 AS delivered,
    SUM(is_failed)                    AS failed,
    COUNT(DISTINCT line_user_id)      AS unique_recipients,
    MIN(time)                         AS time
  FROM ${output_db}.${table_prefix}line_deliveries
  GROUP BY message_key
),
n AS (
  SELECT message_key, MAX_BY(message_name, time) AS message_name
  FROM ${output_db}.${table_prefix}message_names
  GROUP BY message_key
)

SELECT
  'line'                                              AS channel,
  d.message_key,
  COALESCE(n.message_name, d.campaign_name, d.message_key) AS message_label,
  d.campaign_name,
  d.campaign_model,
  d.campaign_id,
  CAST(NULL AS VARCHAR)                               AS custom_event_id,
  d.sender,
  d.first_send_date,
  d.last_send_date,
  d.send_days,
  d.sent,
  d.delivered,
  d.failed,
  CAST(NULL AS BIGINT)                                AS hard_bounced,
  CAST(NULL AS BIGINT)                                AS complained,
  d.failed                                            AS errors,
  CAST(NULL AS BIGINT)                                AS opened,
  CAST(NULL AS BIGINT)                                AS opened_human,
  CAST(NULL AS BIGINT)                                AS clicked,
  CAST(NULL AS BIGINT)                                AS clicked_human,
  CAST(NULL AS BIGINT)                                AS open_count,
  CAST(NULL AS BIGINT)                                AS click_count,
  d.unique_recipients,
  ROUND(d.delivered * 100.0 / NULLIF(d.sent, 0), 2)   AS delivery_rate,
  ROUND(d.failed    * 100.0 / NULLIF(d.sent, 0), 2)   AS failure_rate,
  CAST(NULL AS DOUBLE)                                AS open_rate,
  CAST(NULL AS DOUBLE)                                AS open_rate_human,
  CAST(NULL AS DOUBLE)                                AS click_rate,
  CAST(NULL AS DOUBLE)                                AS click_rate_human,
  CAST(NULL AS DOUBLE)                                AS ctor,
  CAST(NULL AS DOUBLE)                                AS ctor_human,
  TD_TIME_STRING(${session_unixtime}, 's!', '${tz}')  AS updated_at,
  d.time
FROM d
LEFT JOIN n ON n.message_key = d.message_key
