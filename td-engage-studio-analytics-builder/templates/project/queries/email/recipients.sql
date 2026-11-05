-- =====================================================================
-- メール: 1通単位（1行 = 1 message_id = 1受信者への1回の送信）
-- 出力: ${table_prefix}email_recipients（送信日が集計期間内の行を作り直し）
-- ---------------------------------------------------------------------
-- ・events は time = 送信時刻。開封・クリックも送信時刻のパーティションに入るため、
--   送信日で期間を区切れば、遅れて届いた開封・クリックも同じ行にまとまります
-- ・message_key（メッセージ単位のキー）
--     Campaign 機能の送信 : campaign_id（custom_event_id と同じ値）
--     Journey / Activation : custom_event_id
--     どちらもない場合     : template:<email_template_id>
-- ・*_human は is_bot_event = 'Likely' を除いた値（NULL は人として扱う）
-- =====================================================================
WITH src AS (
  SELECT
    time,
    message_id,
    event_type,
    NULLIF(campaign_id, '')        AS campaign_id,
    NULLIF(campaign_name, '')      AS campaign_name,
    NULLIF(campaign_model, '')     AS campaign_model,
    NULLIF(custom_event_id, '')    AS custom_event_id,
    NULLIF(activation_id, '')      AS activation_id,
    NULLIF(activation_name, '')    AS activation_name,
    NULLIF(email_template_id, '')  AS email_template_id,
    email_domain,
    "from"                         AS from_raw,
    LOWER(COALESCE(NULLIF(to_plain_address, ''), REGEXP_EXTRACT("to", '[^<\s]+@[^>\s]+'))) AS to_address,
    subject,
    test_mode,
    COALESCE(is_bot_event, '') = 'Likely' AS is_bot,
    TRY(CAST(TO_UNIXTIME(FROM_ISO8601_TIMESTAMP(delivery_timestamp))  AS BIGINT)) AS delivery_at,
    TRY(CAST(TO_UNIXTIME(FROM_ISO8601_TIMESTAMP(open_timestamp))      AS BIGINT)) AS open_at,
    TRY(CAST(TO_UNIXTIME(FROM_ISO8601_TIMESTAMP(click_timestamp))     AS BIGINT)) AS click_at,
    TRY(CAST(TO_UNIXTIME(FROM_ISO8601_TIMESTAMP(bounce_timestamp))    AS BIGINT)) AS bounce_at,
    TRY(CAST(TO_UNIXTIME(FROM_ISO8601_TIMESTAMP(complaint_timestamp)) AS BIGINT)) AS complaint_at,
    bounce_type,
    bounce_subtype,
    delayed_type,
    complaint_feedback_type,
    reject_reason,
    failure_error_message
  FROM ${email.database}.${email.table}
  WHERE
    time >= IF(${rebuild_all}, 0, TD_TIME_ADD(TD_DATE_TRUNC('day', ${session_unixtime}, '${tz}'), '-${lookback_days}d', '${tz}'))
    AND message_id IS NOT NULL
    AND (NOT ${exclude_test} OR COALESCE(LOWER(CAST(test_mode AS VARCHAR)), 'false') <> 'true')
)

SELECT
  message_id,
  COALESCE(MAX(campaign_id), MAX(custom_event_id), 'template:' || MAX(email_template_id), 'unknown') AS message_key,
  MAX(campaign_id)                                    AS campaign_id,
  MAX(campaign_name)                                  AS campaign_name,
  COALESCE(MAX(campaign_model), IF(MAX(campaign_id) IS NULL, 'Journey/Activation', 'Campaign')) AS campaign_model,
  MAX(custom_event_id)                                AS custom_event_id,
  MAX(activation_id)                                  AS activation_id,
  MAX(activation_name)                                AS activation_name,
  MAX(email_template_id)                              AS email_template_id,
  MAX(email_domain)                                   AS email_domain,
  MAX(REGEXP_EXTRACT(from_raw, '[a-zA-Z0-9_.+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}')) AS from_address,
  MAX(to_address)                                     AS to_address,
  MAX(subject)                                        AS subject,

  -- 送信・到達・エラー
  IF(COUNT_IF(event_type = 'Send') > 0, 1, 0)          AS is_sent,
  IF(COUNT_IF(event_type = 'Delivery') > 0, 1, 0)      AS is_delivered,
  MIN(IF(event_type = 'Delivery', delivery_at))        AS delivered_at,
  IF(COUNT_IF(event_type = 'Bounce') > 0, 1, 0)        AS is_bounced,
  IF(COUNT_IF(event_type = 'Bounce' AND bounce_type = 'Permanent') > 0, 1, 0) AS is_hard_bounced,
  MAX_BY(IF(event_type = 'Bounce', bounce_type), IF(event_type = 'Bounce', bounce_at))       AS bounce_type,
  MAX_BY(IF(event_type = 'Bounce', bounce_subtype), IF(event_type = 'Bounce', bounce_at))    AS bounce_subtype,
  IF(COUNT_IF(event_type = 'Complaint') > 0, 1, 0)     AS is_complained,
  MAX(IF(event_type = 'Complaint', complaint_feedback_type)) AS complaint_feedback_type,
  IF(COUNT_IF(event_type = 'DeliveryDelay') > 0, 1, 0) AS is_delayed,
  MAX(IF(event_type = 'DeliveryDelay', delayed_type))  AS delayed_type,
  IF(COUNT_IF(event_type IN ('Reject', 'RenderingFailure')) > 0, 1, 0) AS is_rejected,
  MAX(COALESCE(reject_reason, failure_error_message))  AS reject_reason,

  -- 開封
  COUNT_IF(event_type = 'Open')                         AS open_count,
  COUNT_IF(event_type = 'Open' AND NOT is_bot)          AS open_count_human,
  IF(COUNT_IF(event_type = 'Open') > 0, 1, 0)           AS is_opened,
  IF(COUNT_IF(event_type = 'Open' AND NOT is_bot) > 0, 1, 0) AS is_opened_human,
  MIN(IF(event_type = 'Open', open_at))                 AS first_open_at,
  MIN(IF(event_type = 'Open' AND NOT is_bot, open_at))  AS first_open_at_human,

  -- クリック
  COUNT_IF(event_type = 'Click')                        AS click_count,
  COUNT_IF(event_type = 'Click' AND NOT is_bot)         AS click_count_human,
  IF(COUNT_IF(event_type = 'Click') > 0, 1, 0)          AS is_clicked,
  IF(COUNT_IF(event_type = 'Click' AND NOT is_bot) > 0, 1, 0) AS is_clicked_human,
  MIN(IF(event_type = 'Click', click_at))               AS first_click_at,
  MIN(IF(event_type = 'Click' AND NOT is_bot, click_at)) AS first_click_at_human,

  IF(MAX(LOWER(CAST(test_mode AS VARCHAR))) = 'true', 1, 0) AS is_test,
  TD_TIME_STRING(MIN(time), 'd!', '${tz}')              AS send_date,
  MIN(time)                                             AS time
FROM src
GROUP BY message_id
