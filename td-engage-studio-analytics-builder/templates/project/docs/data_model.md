# 出力テーブル

出力先は `config/common.yml` の `output_db`、テーブル名の先頭に `table_prefix`（既定 `es_`）が付きます。

## 全体像

```
delivery_email_<domain>.events ──┬─▶ email_recipients   (1通単位)          ─┐
  (error_events)                 ├─▶ email_events_daily (発生日×イベント)   │
                                 ├─▶ email_link_clicks  (リンク別)          │
                                 └─▶ email_errors_daily (送信失敗)          ├─▶ message_summary (メッセージ別・累計)
delivery_line_<id>.<table> ──────────▶ line_deliveries  (1送信リクエスト単位) ├─▶ send_cohort     (送信日×メッセージ)
<insights_db>.message_deliveries ────▶ line_oa_daily    (アカウント日別)      └─▶ daily           (発生日×メッセージ)
                                         message_names  (表示名マスタ・手入力) ─┘
```

| 種類 | テーブル | 更新方法 |
|---|---|---|
| 明細 | `email_recipients`, `email_events_daily`, `email_link_clicks`, `email_errors_daily`, `line_deliveries` | 送信日が直近 `lookback_days` 日の行を削除 → 再集計して追加 |
| 補助 | `line_oa_daily` | 毎回作り直し（`insights_enabled: true` のとき） |
| 共通 | `message_summary`, `send_cohort`, `daily` | 毎回 drop → create → insert |
| マスタ | `message_names` | WFは作成だけ。内容は利用者が登録 |

**ダッシュボード・日次メールは共通テーブル（`message_summary` / `send_cohort` / `daily`）と `email_link_clicks` / `line_oa_daily` だけを参照します。**

## 共通テーブル

### `message_summary`（1行 = チャネル × メッセージ。全期間の累計）

| 列 | 内容 |
|---|---|
| `channel` | `email` / `line` |
| `message_key` | メール: `campaign_id` → `custom_event_id` → `template:<email_template_id>`。LINE: `campaign_id` |
| `message_label` | 表示名。`message_names` → `campaign_name` → 最初に送った件名 → `message_key` |
| `campaign_name`, `campaign_model`, `campaign_id`, `custom_event_id`, `sender` | 属性。`campaign_model` は `Campaign` / `Journey/Activation` |
| `first_send_date`, `last_send_date`, `send_days` | 送信期間 |
| `sent`, `delivered`, `failed`, `hard_bounced`, `complained`, `errors` | 通数 |
| `opened`, `opened_human`, `clicked`, `clicked_human` | 開封・クリックがあった通数（`_human` は Bot 判定 Likely を除外）。LINE は NULL |
| `open_count`, `click_count` | 開封・クリックの延べ回数 |
| `unique_recipients` | ユニーク受信者数 |
| `delivery_rate`, `failure_rate` | ÷ sent（%） |
| `open_rate(_human)`, `click_rate(_human)` | ÷ delivered（%） |
| `ctor(_human)` | clicked ÷ opened（%） |
| `updated_at` | 集計日時 |

### `send_cohort`（1行 = チャネル × 送信日 × メッセージ）

その日に送った通の、集計時点までの結果。**足し上げ可能**なので、期間・メッセージで絞り込んだ率はこのテーブルで計算します。

`channel, send_date, message_key, message_label, sent, delivered, failed, hard_bounced, complained, opened, opened_human, clicked, clicked_human, unique_recipients`

### `daily`（1行 = チャネル × 発生日 × メッセージ）

その日に起きたこと（送信・到達・失敗・開封・クリック）。開封・クリックは「その日に開封された通数」で、過去に送った通も含みます。

`channel, date, message_key, message_label, sent, delivered, failed, complained, errors, opened, opened_human, clicked, clicked_human`

## 明細テーブル

### `email_recipients`（1行 = 1通 = `message_id`）

送信・到達・バウンス（種別）・苦情・遅延・開封（回数・初回時刻・Bot除外）・クリック（同）・テストフラグ・送信日。列は `queries/setup/create_email_recipients.sql` を参照。

### `email_events_daily`（1行 = メッセージ × 送信日 × 発生日 × イベント種別）

`events`（延べ）、`events_human`、`recipients`（通数）、`recipients_human`。

### `email_link_clicks`（1行 = メッセージ × 送信日 × リンク）

`link_url`（クエリ文字列を除いたURL）、`link_example`（完全なURLの例）、`clicks`、`unique_clicks`（通数）、`*_human`。

### `email_errors_daily`（`error_events_enabled: true` のとき）

`error_date`、`error_type`（Runtime Error / Rendering Error）、`error_message_example`、`errors`、`recipients`。

### `line_deliveries`（1行 = 1送信リクエスト。リトライはまとめて最後の結果）

`line_user_id`、`line_request_id`、`api_type`（push 等）、`attempts`、`is_delivered`、`is_failed`、`status_code`、`error_message`、`is_test`、`send_date`。

### `line_oa_daily`（1行 = 日付）

LINE OA Insights（Message Deliveries）の配信種別ごとの送信数。`status = 'ready'` で確定。`api_total` = api_broadcast + api_push + api_multicast、`total` = 全種別の合計。

## `message_names`（表示名マスタ）

Journey の custom_event_id など、名前が分かりにくいメッセージに表示名を付けます。WF 実行後のダッシュボード・メールに反映されます。

```sql
-- 例（Trino）。同じ message_key を複数回登録した場合は time が新しいものを使います
INSERT INTO engage_studio_analytics.es_message_names (message_key, message_name, note, time)
VALUES ('0b1c2d3e-0000-4000-8000-000000000001', '月次ご利用状況レポート', 'Journey: monthly', TD_TIME_PARSE('2026-11-05'))
```

CSV をアップロードして置き換える方法（`tdx table import` 等）でも構いません。

## 列を追加するとき

明細・共通テーブルは `insert_into`（列の**並び順**で追加）を使っています。列を追加するときは、
`queries/setup/create_*.sql` と対応する SELECT の**両方の末尾（`time` の前）**に同じ順番で追加し、`rebuild_all: true` で1回作り直してください。
