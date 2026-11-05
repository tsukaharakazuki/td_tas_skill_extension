-- メール: 送信失敗（queries/email/errors_daily.sql と同じ列順）
-- 列を追加するときは、この定義と SELECT の両方の「末尾（time の前）」に同じ順で追加してください
CREATE TABLE IF NOT EXISTS ${output_db}.${table_prefix}email_errors_daily (
  message_key varchar,
  send_date varchar,
  error_date varchar,
  error_type varchar,
  error_message_example varchar,
  errors bigint,
  recipients bigint,
  time bigint
)
