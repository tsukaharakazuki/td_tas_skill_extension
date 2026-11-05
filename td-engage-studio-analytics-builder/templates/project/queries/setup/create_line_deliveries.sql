-- LINE: 1送信リクエスト単位（queries/line/deliveries_*.sql と同じ列順）
-- 列を追加するときは、この定義と SELECT の両方の「末尾（time の前）」に同じ順で追加してください
CREATE TABLE IF NOT EXISTS ${output_db}.${table_prefix}line_deliveries (
  delivery_id varchar,
  message_key varchar,
  campaign_id varchar,
  campaign_name varchar,
  campaign_model varchar,
  line_channel_name varchar,
  message_type varchar,
  line_user_id varchar,
  line_request_id varchar,
  api_type varchar,
  attempts bigint,
  is_delivered bigint,
  is_failed bigint,
  status_code varchar,
  error_message varchar,
  is_test bigint,
  send_date varchar,
  time bigint
)
