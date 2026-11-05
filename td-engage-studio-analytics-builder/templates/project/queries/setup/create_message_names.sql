-- メッセージ表示名のマスタ（任意）。message_key ごとに分かりやすい名前を登録すると、ダッシュボードとメールに表示されます
-- 列を追加するときは、この定義と SELECT の両方の「末尾（time の前）」に同じ順で追加してください
CREATE TABLE IF NOT EXISTS ${output_db}.${table_prefix}message_names (
  message_key varchar,
  message_name varchar,
  note varchar,
  time bigint
)
