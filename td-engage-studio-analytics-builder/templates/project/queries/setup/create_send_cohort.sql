-- 全チャネル: 送信日 × メッセージ（queries/unified/send_cohort_*.sql と同じ列順）
-- その日に送った通が「その後どうなったか」（到達・開封・クリック）を集計時点の累計で持ちます
-- 足し上げできるため、ダッシュボードで期間・メッセージを絞り込んだ率の計算に使います
-- 毎回 drop → create → insert で作り直します
CREATE TABLE IF NOT EXISTS ${output_db}.${table_prefix}send_cohort (
  channel varchar,
  send_date varchar,
  message_key varchar,
  message_label varchar,
  sent bigint,
  delivered bigint,
  failed bigint,
  hard_bounced bigint,
  complained bigint,
  opened bigint,
  opened_human bigint,
  clicked bigint,
  clicked_human bigint,
  unique_recipients bigint,
  time bigint
)
