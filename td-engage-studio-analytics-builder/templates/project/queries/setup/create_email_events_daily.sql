-- メール: 発生日 × メッセージ × イベント種別（queries/email/events_daily.sql と同じ列順）
-- 列を追加するときは、この定義と SELECT の両方の「末尾（time の前）」に同じ順で追加してください
CREATE TABLE IF NOT EXISTS ${output_db}.${table_prefix}email_events_daily (
  message_key varchar,
  send_date varchar,
  event_date varchar,
  event_type varchar,
  events bigint,
  events_human bigint,
  recipients bigint,
  recipients_human bigint,
  time bigint
)
