-- ダッシュボード用: 送信日 × メッセージ（KPI・推移・メッセージ表の元データ）
SELECT
  channel, send_date, message_key, message_label,
  sent, delivered, failed, opened, opened_human, clicked, clicked_human
FROM ${output_db}.${table_prefix}send_cohort
WHERE send_date >= '${since_date}'
