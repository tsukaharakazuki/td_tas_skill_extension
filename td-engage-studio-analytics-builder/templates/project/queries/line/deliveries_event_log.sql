-- =====================================================================
-- LINE: 1レコード単位（log_format: event_log）
-- 出力: ${table_prefix}line_deliveries（送信日が集計期間内の行を作り直し）
-- ---------------------------------------------------------------------
-- ドキュメント記載の形式:
--   event（delivery / error）/ status（success / failed）/ error_code /
--   channel_type / campaign_id / line_channel_name / message_type / test_mode
-- ・この形式にはユーザーIDの記載がないため、line_user_id は NULL（ユニーク人数は出ません）
--   実テーブルにユーザーIDの列がある場合は line_user_id を置き換えてください
-- =====================================================================
SELECT
  CAST(time AS VARCHAR) || ':' || CAST(ROW_NUMBER() OVER (PARTITION BY time ORDER BY campaign_id) AS VARCHAR) AS delivery_id,
  COALESCE(NULLIF(campaign_id, ''), 'unknown')       AS message_key,
  NULLIF(campaign_id, '')                            AS campaign_id,
  CAST(NULL AS VARCHAR)                              AS campaign_name,
  'Campaign'                                         AS campaign_model,
  line_channel_name,
  message_type,
  CAST(NULL AS VARCHAR)                              AS line_user_id,
  CAST(NULL AS VARCHAR)                              AS line_request_id,
  CAST(NULL AS VARCHAR)                              AS api_type,
  1                                                  AS attempts,
  IF(event = 'delivery' AND status = 'success', 1, 0) AS is_delivered,
  IF(event = 'error' OR status = 'failed', 1, 0)     AS is_failed,
  CAST(status AS VARCHAR)                            AS status_code,
  CAST(error_code AS VARCHAR)                        AS error_message,
  IF(LOWER(CAST(test_mode AS VARCHAR)) = 'true', 1, 0) AS is_test,
  TD_TIME_STRING(time, 'd!', '${tz}')                AS send_date,
  time
FROM ${line.database}.${line.table}
WHERE
  time >= IF(${rebuild_all}, 0, TD_TIME_ADD(TD_DATE_TRUNC('day', ${session_unixtime}, '${tz}'), '-${lookback_days}d', '${tz}'))
  AND (NOT ${exclude_test} OR COALESCE(LOWER(CAST(test_mode AS VARCHAR)), 'false') <> 'true')
