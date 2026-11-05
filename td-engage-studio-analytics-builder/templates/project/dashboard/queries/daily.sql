-- ダッシュボード用: 発生日別の開封・クリック（メールのみ。メッセージ単位に絞り込めるよう message_key を残す）
SELECT
  channel, date, message_key, opened, opened_human, clicked, clicked_human
FROM ${output_db}.${table_prefix}daily
WHERE channel = 'email'
  AND date >= '${since_date}'
  AND (opened > 0 OR clicked > 0)
