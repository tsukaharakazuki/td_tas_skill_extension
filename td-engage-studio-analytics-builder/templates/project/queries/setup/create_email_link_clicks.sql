-- メール: メッセージ × リンク別クリック（queries/email/link_clicks.sql と同じ列順）
-- 列を追加するときは、この定義と SELECT の両方の「末尾（time の前）」に同じ順で追加してください
CREATE TABLE IF NOT EXISTS ${output_db}.${table_prefix}email_link_clicks (
  message_key varchar,
  send_date varchar,
  link_url varchar,
  link_example varchar,
  clicks bigint,
  clicks_human bigint,
  unique_clicks bigint,
  unique_clicks_human bigint,
  time bigint
)
