# LINE の開封・クリックと LINE OA Insights の設定

Engage Studio の LINE 配信ログには、**開封・クリックが含まれません**（LINE が個別ユーザーの開封・クリックを提供していないため）。
このWFでは、LINE は「配信数・到達数・失敗数」をメッセージ単位で集計し、開封・クリックは「—」と表示します。

開封・クリックや、アカウント全体の配信数が必要な場合は、Integration Hub の **LINE OA Insights** 取り込みを追加します。

## まず確認すること（ヒアリング）

1. LINE の開封数・クリック数をレポートに出す必要があるか
   - 不要 → `config/line.yml` は `insights_enabled: false` のまま。配信ログの集計だけで運用
   - 必要 → 下の「選べるデータ」と制約を説明し、取り込む Target を決める
2. LINE公式アカウントの **長期チャネルアクセストークン** を、お客様自身が Integration Hub に登録できるか（チャットに貼ってもらわない）
3. 取り込み先のDB・テーブル名（例: `line_oa_reporting.message_deliveries`）

## 選べるデータ（Target）

| Target | 中身 | このWFでの扱い |
|---|---|---|
| **Message Deliveries** | 日別 × 配信種別（broadcast / api_push / api_multicast …）の送信数 | `insights_enabled: true` で `${table_prefix}line_oa_daily` に整形し、ダッシュボードと日次メールに表示 |
| User Interaction Statistics | LINE の request ID を指定した、メッセージ単位の開封・クリックなどの統計 | 自動集計はしない（下記の制約あり）。取り込み後に列を確認して個別に追加 |
| Followers | 日別の友だち数・ブロック数 | 対象外（必要なら追加） |
| Demographics | 友だちの属性構成 | 対象外 |

> ドキュメントには「Message Deliveries はブロードキャスト単位の配信・開封・クリック数」とありますが、
> 2026-11 時点の実データは「日別 × 配信種別の送信数」で、開封・クリックは含まれていませんでした。
> 取り込み後に `tdx describe <db>.<table>` で列を確認してください。

### User Interaction Statistics の制約

- LINE 側で統計が返るのは、主に **一斉配信（broadcast）・セグメント配信（narrowcast）** のメッセージです。Engage Studio の LINE 送信は **ユーザーごとの Push** のため、request ID ごとの統計が取れない、または少人数のため数値が出ない（LINE は一定人数未満の統計を返さない）ことがあります。
- 指定する request ID は配信ログの `line_request_id`（`${table_prefix}line_deliveries.line_request_id`）から取得できます。
- 取れるかどうかは、**数件の request ID でテスト取り込みしてから** 判断してください。URL単位のクリックが必要な場合は、リンクに UTM パラメータを付けて Web 解析側で計測する方法を勧めます。

## 設定手順（Message Deliveries）

お客様（またはTD担当）がコンソールで行います。

1. Treasure Console → **Integrations Hub → Catalog** で「LINE OA Insights」を検索し、Authentication を作成
   - LINE Developers Console → 対象チャネル → Messaging API タブの **長期チャネルアクセストークン** を入力
2. 作成した Authentication から **New Source**
   - Target: `Message Deliveries`
   - Start Date: 集計を始めたい日（`yyyyMMdd`）
   - Incremental: **ON**（前回以降の新しい日付だけ取り込む）
3. 取り込み先 DB / テーブル（例 `line_oa_reporting` / `message_deliveries`）、Method: Append
4. Schedule: **毎日**（このWFの実行より前の時刻。例: 毎日 06:00 JST、WFは 08:00）
5. Create & Run Now

### Workflow で取り込む場合（任意）

Source を作らず WF から取り込むこともできます。トークンは必ず Secret に登録してください（`.dig` や yml に直接書かない）。

```yaml
# 例: line_oa_insights_import.dig（このパッケージには含めていません）
+import_line_oa_insights:
  td_load>: imports/line_oa_insights.yml
  database: line_oa_reporting
  table: message_deliveries
```

```yaml
# imports/line_oa_insights.yml
in:
  type: line_oa_insights
  channel_access_token: ${secret:line.channel_access_token}
  target: message_deliveries
  start_date: "20260101"
  incremental: true
out:
  mode: append
```

Secret の登録はお客様自身が行います: TD Console → Workflows → プロジェクト → Secrets（キー `line.channel_access_token`）。

## このWFでの有効化

```yaml
# config/line.yml
line:
  enabled: true
  insights_enabled: true
  insights_database: line_oa_reporting
  insights_table: message_deliveries
```

確認クエリ（読み取りのみ）:

```sql
SELECT query_date, status, api_push, api_multicast, broadcast
FROM line_oa_reporting.message_deliveries
ORDER BY query_date DESC
LIMIT 10
```

- Insights API は 1時間あたり60リクエストまで。統計の確定は配信の1〜3日後（`status = 'ready'`）。
- アカウント全体の数値のため、Engage Studio 以外（LINE公式アカウント管理画面からの配信・自動応答など）も含みます。
