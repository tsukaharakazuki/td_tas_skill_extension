-- =====================================================================
-- メール: 送信失敗（error_events）発生日 × メッセージ × エラー種別
-- 出力: ${table_prefix}email_errors_daily（config/email.yml の error_events_enabled: true のときだけ実行）
-- ---------------------------------------------------------------------
-- error_type: Runtime Error（送信処理の失敗）/ Rendering Error（テンプレートの描画失敗）
-- error_events には campaign_id がないため、message_key は custom_event_id を使います
--   （Campaign 機能の送信では custom_event_id = campaign_id）
-- =====================================================================
SELECT
  COALESCE(NULLIF(custom_event_id, ''), 'template:' || email_template_id, 'unknown') AS message_key,
  TD_TIME_STRING(time, 'd!', '${tz}')                         AS send_date,
  TD_TIME_STRING(COALESCE(error_time, time), 'd!', '${tz}')   AS error_date,
  error_type,
  SUBSTR(MAX(error_message), 1, 500)                          AS error_message_example,
  COUNT(1)                                                    AS errors,
  COUNT(DISTINCT LOWER(to_plain_address))                     AS recipients,
  MIN(time)                                                   AS time
FROM ${email.database}.${email.error_table}
WHERE
  time >= IF(${rebuild_all}, 0, TD_TIME_ADD(TD_DATE_TRUNC('day', ${session_unixtime}, '${tz}'), '-${lookback_days}d', '${tz}'))
GROUP BY 1, 2, 3, 4
