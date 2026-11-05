-- LINE OA Insights: 日別配信数（queries/line/oa_daily.sql と同じ列順）
-- 列を追加するときは、この定義と SELECT の両方の「末尾（time の前）」に同じ順で追加してください
CREATE TABLE IF NOT EXISTS ${output_db}.${table_prefix}line_oa_daily (
  date varchar,
  status varchar,
  broadcast bigint,
  targeting bigint,
  step_message bigint,
  auto_response bigint,
  welcome_response bigint,
  chat bigint,
  api_broadcast bigint,
  api_push bigint,
  api_multicast bigint,
  api_reply bigint,
  api_total bigint,
  total bigint,
  time bigint
)
