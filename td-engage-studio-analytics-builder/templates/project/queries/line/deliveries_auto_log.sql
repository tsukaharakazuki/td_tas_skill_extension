-- =====================================================================
-- LINE: 1送信リクエスト単位（log_format: auto_log）
-- 出力: ${table_prefix}line_deliveries（送信日が集計期間内の行を作り直し）
-- ---------------------------------------------------------------------
-- 対象の列: delivered / status / response_status_code / error / retry_key / will_retry /
--           line_user_id / line_request_id / api_endpoint / campaign_id / campaign_name / test_mode
-- ・リトライは retry_key（なければ event_id）でまとめ、最後の結果を採用します
-- ・開封・クリックは配信ログにありません（LINE の仕様）。docs/line_insights_setup.md を参照
-- =====================================================================
WITH src AS (
  SELECT
    time,
    COALESCE(NULLIF(retry_key, ''), NULLIF(event_id, ''), line_request_id, CAST(time AS VARCHAR) || ':' || COALESCE(line_user_id, '')) AS delivery_id,
    NULLIF(campaign_id, '')    AS campaign_id,
    NULLIF(campaign_name, '')  AS campaign_name,
    NULLIF(campaign_model, '') AS campaign_model,
    line_user_id,
    line_request_id,
    api_endpoint,
    COALESCE(
      LOWER(CAST(delivered AS VARCHAR)) = 'true',
      COALESCE(response_status_code, status) BETWEEN 200 AND 299,
      false)                   AS is_ok,
    COALESCE(response_status_code, status) AS status_code,
    NULLIF(CAST(error AS VARCHAR), '') AS error_message,
    LOWER(CAST(test_mode AS VARCHAR)) = 'true' AS is_test
  FROM ${line.database}.${line.table}
  WHERE
    time >= IF(${rebuild_all}, 0, TD_TIME_ADD(TD_DATE_TRUNC('day', ${session_unixtime}, '${tz}'), '-${lookback_days}d', '${tz}'))
    AND (NOT ${exclude_test} OR COALESCE(LOWER(CAST(test_mode AS VARCHAR)), 'false') <> 'true')
)

SELECT
  delivery_id,
  COALESCE(MAX(campaign_id), 'unknown')            AS message_key,
  MAX(campaign_id)                                  AS campaign_id,
  MAX(campaign_name)                                AS campaign_name,
  COALESCE(MAX(campaign_model), 'Journey/Activation') AS campaign_model,
  CAST(NULL AS VARCHAR)                             AS line_channel_name,
  CAST(NULL AS VARCHAR)                             AS message_type,
  MAX(line_user_id)                                 AS line_user_id,
  MAX_BY(line_request_id, time)                     AS line_request_id,
  REGEXP_EXTRACT(MAX(api_endpoint), '[^/]+$')       AS api_type,
  COUNT(1)                                          AS attempts,
  IF(MAX_BY(is_ok, time), 1, 0)                     AS is_delivered,
  IF(MAX_BY(is_ok, time), 0, 1)                     AS is_failed,
  CAST(MAX_BY(status_code, time) AS VARCHAR)        AS status_code,
  SUBSTR(MAX_BY(error_message, time), 1, 500)       AS error_message,
  IF(BOOL_OR(is_test), 1, 0)                        AS is_test,
  TD_TIME_STRING(MIN(time), 'd!', '${tz}')          AS send_date,
  MIN(time)                                         AS time
FROM src
GROUP BY delivery_id
