-- ダッシュボード用: メッセージのマスタ情報（ラベル・送信方法・送信期間）
SELECT
  channel, message_key, message_label, campaign_model, campaign_name, campaign_id, custom_event_id,
  sender, first_send_date, last_send_date, sent
FROM ${output_db}.${table_prefix}message_summary
WHERE last_send_date >= '${since_date}'
