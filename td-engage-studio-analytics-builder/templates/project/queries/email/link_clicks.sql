-- =====================================================================
-- メール: メッセージ × リンク別クリック
-- 出力: ${table_prefix}email_link_clicks（送信日が集計期間内の行を作り直し）
-- ---------------------------------------------------------------------
-- ・link_url はクエリ文字列（?以降）を除いたURL。click_link の完全なURLは link_example に1件残します
-- =====================================================================
WITH src AS (
  SELECT
    time,
    message_id,
    COALESCE(NULLIF(campaign_id, ''), NULLIF(custom_event_id, ''), 'template:' || email_template_id, 'unknown') AS message_key,
    COALESCE(is_bot_event, '') = 'Likely' AS is_bot,
    click_link,
    REGEXP_REPLACE(click_link, '[?#].*$', '') AS link_url
  FROM ${email.database}.${email.table}
  WHERE
    time >= IF(${rebuild_all}, 0, TD_TIME_ADD(TD_DATE_TRUNC('day', ${session_unixtime}, '${tz}'), '-${lookback_days}d', '${tz}'))
    AND event_type = 'Click'
    AND click_link IS NOT NULL
    AND (NOT ${exclude_test} OR COALESCE(LOWER(CAST(test_mode AS VARCHAR)), 'false') <> 'true')
)

SELECT
  message_key,
  TD_TIME_STRING(time, 'd!', '${tz}')        AS send_date,
  link_url,
  MAX(click_link)                            AS link_example,
  COUNT(1)                                   AS clicks,
  COUNT_IF(NOT is_bot)                       AS clicks_human,
  COUNT(DISTINCT message_id)                 AS unique_clicks,
  COUNT(DISTINCT IF(NOT is_bot, message_id)) AS unique_clicks_human,
  MIN(time)                                  AS time
FROM src
GROUP BY 1, 2, 3
