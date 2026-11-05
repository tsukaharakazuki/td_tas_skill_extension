-- =====================================================================
-- LINE OA Insights: 日別の配信数（Target = Message Deliveries）
-- 出力: ${table_prefix}line_oa_daily（毎回作り直し）
-- ---------------------------------------------------------------------
-- ・LINE公式アカウント全体の「送信したメッセージ数」を配信種別ごとに日別で持つテーブルです
--   （Engage Studio のメッセージ単位ではありません。開封・クリックも含まれません）
-- ・append 取り込みで同じ日付が重複するため、query_date ごとに1行（status = ready を優先）にします
-- ・status が ready になるまで（配信の1〜3日後）は数値が確定しません
-- =====================================================================
WITH ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY query_date ORDER BY IF(status = 'ready', 0, 1), time DESC) AS rn
  FROM ${line.insights_database}.${line.insights_table}
  WHERE query_date IS NOT NULL
)

SELECT
  DATE_FORMAT(DATE_PARSE(query_date, '%Y%m%d'), '%Y-%m-%d') AS date,
  status,
  COALESCE(broadcast, 0)              AS broadcast,
  COALESCE(targeting, 0)              AS targeting,
  COALESCE(step_message, 0)           AS step_message,
  COALESCE(auto_response, 0)          AS auto_response,
  COALESCE(welcome_response, 0)       AS welcome_response,
  COALESCE(chat, 0)                   AS chat,
  COALESCE(api_broadcast, 0)          AS api_broadcast,
  COALESCE(api_push, 0)               AS api_push,
  COALESCE(api_multicast, 0)          AS api_multicast,
  COALESCE(api_reply, 0)              AS api_reply,
  COALESCE(api_broadcast, 0) + COALESCE(api_push, 0) + COALESCE(api_multicast, 0) AS api_total,
  COALESCE(broadcast, 0) + COALESCE(targeting, 0) + COALESCE(step_message, 0) + COALESCE(auto_response, 0)
    + COALESCE(welcome_response, 0) + COALESCE(chat, 0) + COALESCE(api_broadcast, 0) + COALESCE(api_push, 0)
    + COALESCE(api_multicast, 0) + COALESCE(api_reply, 0) AS total,
  TD_TIME_PARSE(DATE_FORMAT(DATE_PARSE(query_date, '%Y%m%d'), '%Y-%m-%d'), '${tz}') AS time
FROM ranked
WHERE rn = 1
