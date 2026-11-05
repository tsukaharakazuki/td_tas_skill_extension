# 参照する配信ログの列（2026-11 確認）

公式ドキュメントと、実環境の直近データ（2026-10〜11）を突き合わせた結果です。
**ドキュメントと実データで違う点があるため、新しい環境では必ず `tdx describe` と下の確認クエリで実データを見てから設定してください。**

- Email delivery events: https://docs.treasure.ai/products/marketing-cloud/engage-studio/channels/email/email-delivery-events-table
- Email error events: https://docs.treasure.ai/products/marketing-cloud/engage-studio/channels/email/email-error-events-table
- LINE delivery log / LINE campaign reporting: https://docs.treasure.ai/products/marketing-cloud/engage-studio/channels/line/line-oa-reporting

## 1. メール `delivery_email_<送信ドメイン>.events`

1行 = 1イベント（Send / Delivery / Open / Click / Bounce / Complaint / DeliveryDelay）。`message_id` は SES のメッセージID（1受信者への1回の送信）。

| 列 | 実データの型 | 使い方 / 実データで分かったこと |
|---|---|---|
| `time` | bigint | **送信時刻（`timestamp` と同じ）**。ドキュメントでは delivery_timestamp 相当とあるが、実データでは Open / Click も送信時刻のパーティションに入る。→ 送信日で集計期間を区切って作り直す設計にした |
| `event_type` | varchar | Send / Delivery / Open / Click / Bounce（直近30日の実データ）。Complaint / DeliveryDelay も集計対象 |
| `message_id` | varchar | 1通のキー。集計の最小単位 |
| `campaign_id` / `campaign_name` / `campaign_model` | varchar | **Campaign 機能の送信だけ値が入る**（`campaign_model = 'Campaign'`）。Journey / Activation の送信では NULL |
| `custom_event_id` | varchar | Journey / Activation の送信で入ることが多い。Campaign 送信では `campaign_id` と同じ値。**`campaign_id` / `custom_event_id` が両方 NULL の行はテスト送信（`test_mode = true`）だけで確認した**（直近60日で4通）。その場合 `message_key` は `template:<email_template_id>` にフォールバックするため集計に影響しない |
| `activation_id` / `activation_name` | varchar | Campaign 送信で入る（`engage_campaign_<id>`）。ドキュメントでは出力マッピングで追加される列 |
| `email_template_id` | varchar | 1つの custom_event_id に複数テンプレートが紐づくことがある |
| `subject` | varchar | **受信者ごとに差し込みで変わる**ことがある（1メッセージで数百種類）。メッセージのキーには使えない |
| `from` / `to` / `to_plain_address` | varchar | `to_plain_address` を受信者アドレスに使う |
| `test_mode` | **varchar**（'true' / 'false' / NULL） | ドキュメントは boolean。古いデータは NULL。`COALESCE(LOWER(test_mode),'false') <> 'true'` で除外 |
| `is_bot_event` | varchar | Open / Click のみ 'Likely' / 'Unlikely'。直近30日で Open の約3割が Likely |
| `delivery_timestamp` / `open_timestamp` / `click_timestamp` / `bounce_timestamp` / `complaint_timestamp` / `delayed_timestamp` | varchar（ISO8601） | イベントの発生時刻。`FROM_ISO8601_TIMESTAMP` で変換 |
| `click_link` | varchar | クリックされたURL |
| `bounce_type` / `bounce_subtype` | varchar | Permanent / Transient / Undetermined |
| その他 | varchar | `delivery_*`, `bounce_recipient_*`, `delayed_*`, `complaint_*`, `reject_reason`, `failure_error_message` |

**遅延の実測（直近60日）**: Open は送信から 中央値0時間 / 90%点 65時間 / 99%点 約21日 / 最大 約43日。Click は 99%点 約23日。→ `lookback_days: 60` を既定にした。

### メッセージ単位のキー（message_key）

```
COALESCE(campaign_id, custom_event_id, 'template:' || email_template_id, 'unknown')
```

### error_events

ドキュメントでは同じDBに `error_events`（`error_type` = Runtime Error / Rendering Error、`error_message`、`error_time` など）がある。**確認した環境には存在しなかった**ため、`config/email.yml` の `error_events_enabled` で有効化する方式にした。`campaign_id` 列はないため `custom_event_id` で紐づける。

## 2. LINE 配信ログ `delivery_line_<system_identifier>.<table>`

ドキュメントと実テーブルの列構成が異なる。`config/line.yml` の `log_format` で切り替える。

| 形式 | 主な列 | 判定 |
|---|---|---|
| `auto_log`（実環境 2026-08） | `delivered`('true'/'false'), `status`(HTTPコード bigint), `response_status_code`, `error`, `retry_key`, `retry_count`, `will_retry`, `line_user_id`, `line_request_id`, `api_endpoint`(…/message/push), `campaign_id`, `campaign_name`, `campaign_model`, `test_mode`(varchar), `request_time` | テーブル名 `line_events`。到達 = `delivered = 'true'` または 2xx |
| `event_log`（ドキュメント） | `event`(delivery / error), `status`(success / failed), `error_code`, `channel_type`, `campaign_id`, `line_channel_name`, `message_type`, `test_mode` | 到達 = `event = 'delivery' AND status = 'success'` |

- 開封・クリックは配信ログに**含まれない**（LINE の仕様）。
- `test_mode` は 2026-08-10 以前のデータでは NULL のことがある。

## 3. LINE OA Insights `<db>.message_deliveries`（Integration Hub「LINE OA Insights」）

ドキュメントでは「ブロードキャスト単位の配信数・開封数・クリック数」とあるが、**実際に取り込まれたテーブルは「日別 × 配信種別の送信数」**だった（LINE Messaging API の「送信済みメッセージ数」）。

| 列 | 内容 |
|---|---|
| `query_date` | 対象日（yyyyMMdd） |
| `status` | `ready` で確定（配信の1〜3日後）。それまでは `unready` 等 |
| `broadcast`, `targeting`, `step_message`, `auto_response`, `welcome_response`, `chat`, `api_broadcast`, `api_push`, `api_multicast`, `api_reply`, `cc_auto_reply`, `cc_manual_reply`, `pnp_notice_message`, `pnp_call_to_line`, `third_party_chat_tool` | 配信種別ごとの送信数 |
| `time` | query_date の 00:00（JST） |

- Engage Studio の LINE 送信は API Push（`api_push`）として数えられる。
- 開封・クリックは含まれない。メッセージ単位の開封・クリックは Target = **User Interaction Statistics**（LINE の request ID 指定）で取得する。詳しくは [line_insights_setup.md](line_insights_setup.md)。

## 確認クエリ（読み取りのみ）

```sql
-- メール: 直近30日のイベント種別・テスト・Bot判定の内訳
SELECT event_type, test_mode, campaign_model, is_bot_event,
       COUNT(1) AS events, COUNT(DISTINCT message_id) AS messages,
       COUNT(DISTINCT campaign_id) AS campaigns, COUNT(DISTINCT custom_event_id) AS custom_events
FROM delivery_email_<domain>.events
WHERE TD_INTERVAL(time, '-30d', 'JST')
GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4

-- メール: time と送信時刻（timestamp）の関係、開封の遅延
SELECT event_type,
       APPROX_PERCENTILE(DATE_DIFF('hour', FROM_ISO8601_TIMESTAMP("timestamp"),
         FROM_ISO8601_TIMESTAMP(COALESCE(open_timestamp, click_timestamp, bounce_timestamp, delivery_timestamp, "timestamp"))), ARRAY[0.5, 0.9, 0.99]) AS lag_hours
FROM delivery_email_<domain>.events
WHERE TD_INTERVAL(time, '-60d', 'JST')
GROUP BY 1

-- LINE: 列構成と件数
SELECT COUNT(1), MIN(TD_TIME_STRING(time, 'd!', 'JST')), MAX(TD_TIME_STRING(time, 'd!', 'JST'))
FROM delivery_line_<id>.<table>
```
