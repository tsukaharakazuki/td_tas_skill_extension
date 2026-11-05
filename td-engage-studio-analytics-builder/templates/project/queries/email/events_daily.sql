-- =====================================================================
-- メール: 発生日 × メッセージ × イベント種別
-- 出力: ${table_prefix}email_events_daily（送信日が集計期間内の行を作り直し）
-- ---------------------------------------------------------------------
-- ・event_date はイベントが「起きた日」（開封なら open_timestamp の日付）
-- ・send_date は送信日。time = その送信日の最初の送信時刻（期間の作り直しに使用）
-- ・recipients は、その日にそのイベントがあった通数（message_id のユニーク数）
-- =====================================================================
WITH src AS (
  SELECT
    time,
    message_id,
    event_type,
    COALESCE(NULLIF(campaign_id, ''), NULLIF(custom_event_id, ''), 'template:' || email_template_id, 'unknown') AS message_key,
    COALESCE(is_bot_event, '') = 'Likely' AS is_bot,
    COALESCE(
      TRY(CAST(TO_UNIXTIME(FROM_ISO8601_TIMESTAMP(
        CASE event_type
          WHEN 'Delivery'      THEN delivery_timestamp
          WHEN 'Open'          THEN open_timestamp
          WHEN 'Click'         THEN click_timestamp
          WHEN 'Bounce'        THEN bounce_timestamp
          WHEN 'Complaint'     THEN complaint_timestamp
          WHEN 'DeliveryDelay' THEN delayed_timestamp
          ELSE "timestamp"
        END)) AS BIGINT)),
      time) AS event_at
  FROM ${email.database}.${email.table}
  WHERE
    time >= IF(${rebuild_all}, 0, TD_TIME_ADD(TD_DATE_TRUNC('day', ${session_unixtime}, '${tz}'), '-${lookback_days}d', '${tz}'))
    AND message_id IS NOT NULL
    AND event_type IS NOT NULL
    AND (NOT ${exclude_test} OR COALESCE(LOWER(CAST(test_mode AS VARCHAR)), 'false') <> 'true')
)

SELECT
  message_key,
  TD_TIME_STRING(time, 'd!', '${tz}')       AS send_date,
  TD_TIME_STRING(event_at, 'd!', '${tz}')   AS event_date,
  event_type,
  COUNT(1)                                  AS events,
  COUNT_IF(NOT is_bot)                      AS events_human,
  COUNT(DISTINCT message_id)                AS recipients,
  COUNT(DISTINCT IF(NOT is_bot, message_id)) AS recipients_human,
  MIN(time)                                 AS time
FROM src
GROUP BY 1, 2, 3, 4
