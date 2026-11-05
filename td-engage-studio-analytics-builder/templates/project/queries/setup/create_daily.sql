-- 全チャネル: 日別 × メッセージ（queries/unified/daily_*.sql と同じ列順）
-- date はイベントが起きた日（メール: 開封・クリックは開封日・クリック日 / LINE: 送信日）
-- 毎回 drop → create → insert で作り直します
CREATE TABLE IF NOT EXISTS ${output_db}.${table_prefix}daily (
  channel varchar,
  date varchar,
  message_key varchar,
  message_label varchar,
  sent bigint,
  delivered bigint,
  failed bigint,
  complained bigint,
  errors bigint,
  opened bigint,
  opened_human bigint,
  clicked bigint,
  clicked_human bigint,
  time bigint
)
