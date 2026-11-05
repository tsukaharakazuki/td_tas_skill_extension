-- =====================================================================
-- 全チャネル: メッセージ単位サマリー（メール分）
-- 出力: ${table_prefix}message_summary に追加（channel = 'email'）
-- ---------------------------------------------------------------------
-- 指標の定義（ユニーク = 通数。1通に複数回開封しても1）
--   sent        : Send イベントがあった通数（SES受付。抑止リスト分も含む）
--   delivered   : Delivery があった通数（受信サーバーが受け付けた）
--   failed      : Bounce があった通数（hard_bounced は Permanent のみ）
--   opened      : Open があった通数（*_human は is_bot_event = 'Likely' を除外）
--   clicked     : Click があった通数
--   open_rate   : opened / delivered（%）
--   click_rate  : clicked / delivered（%）
--   ctor        : clicked / opened（%）
--   label       : message_names の登録名 → campaign_name → 最初に送った件名 の順で採用
-- =====================================================================
WITH r AS (
  SELECT
    message_key,
    MAX(campaign_name)                 AS campaign_name,
    MAX(campaign_model)                AS campaign_model,
    MAX(campaign_id)                   AS campaign_id,
    MAX(custom_event_id)               AS custom_event_id,
    MAX(from_address)                  AS sender,
    MIN_BY(subject, time)              AS first_subject,
    MIN(send_date)                     AS first_send_date,
    MAX(send_date)                     AS last_send_date,
    COUNT(DISTINCT send_date)          AS send_days,
    SUM(is_sent)                       AS sent,
    SUM(is_delivered)                  AS delivered,
    SUM(is_bounced)                    AS failed,
    SUM(is_hard_bounced)               AS hard_bounced,
    SUM(is_complained)                 AS complained,
    SUM(is_opened)                     AS opened,
    SUM(is_opened_human)               AS opened_human,
    SUM(is_clicked)                    AS clicked,
    SUM(is_clicked_human)              AS clicked_human,
    SUM(open_count)                    AS open_count,
    SUM(click_count)                   AS click_count,
    COUNT(DISTINCT to_address)         AS unique_recipients,
    MIN(time)                          AS time
  FROM ${output_db}.${table_prefix}email_recipients
  GROUP BY message_key
),
e AS (
  SELECT message_key, SUM(errors) AS errors
  FROM ${output_db}.${table_prefix}email_errors_daily
  GROUP BY message_key
),
n AS (
  SELECT message_key, MAX_BY(message_name, time) AS message_name
  FROM ${output_db}.${table_prefix}message_names
  GROUP BY message_key
)

SELECT
  'email'                                             AS channel,
  r.message_key,
  COALESCE(n.message_name, r.campaign_name, r.first_subject, r.message_key) AS message_label,
  r.campaign_name,
  r.campaign_model,
  r.campaign_id,
  r.custom_event_id,
  r.sender,
  r.first_send_date,
  r.last_send_date,
  r.send_days,
  r.sent,
  r.delivered,
  r.failed,
  r.hard_bounced,
  r.complained,
  COALESCE(e.errors, 0)                               AS errors,
  r.opened,
  r.opened_human,
  r.clicked,
  r.clicked_human,
  r.open_count,
  r.click_count,
  r.unique_recipients,
  ROUND(r.delivered     * 100.0 / NULLIF(r.sent, 0), 2)      AS delivery_rate,
  ROUND(r.failed        * 100.0 / NULLIF(r.sent, 0), 2)      AS failure_rate,
  ROUND(r.opened        * 100.0 / NULLIF(r.delivered, 0), 2) AS open_rate,
  ROUND(r.opened_human  * 100.0 / NULLIF(r.delivered, 0), 2) AS open_rate_human,
  ROUND(r.clicked       * 100.0 / NULLIF(r.delivered, 0), 2) AS click_rate,
  ROUND(r.clicked_human * 100.0 / NULLIF(r.delivered, 0), 2) AS click_rate_human,
  ROUND(r.clicked       * 100.0 / NULLIF(r.opened, 0), 2)    AS ctor,
  ROUND(r.clicked_human * 100.0 / NULLIF(r.opened_human, 0), 2) AS ctor_human,
  TD_TIME_STRING(${session_unixtime}, 's!', '${tz}')          AS updated_at,
  r.time
FROM r
LEFT JOIN e ON e.message_key = r.message_key
LEFT JOIN n ON n.message_key = r.message_key
