# ジャーニーのアクティベーション（Engage Studio 連携）

出典: td-tdx-activation / td-tdx-connector-config / cjo-journey-tips を、tdx 2026.10.4 のスキーマと `tdx connection schema treasure_engage_v1` で補正。

## 1. YAML で書けること・書けないこと

| 設定 | YAML（`tdx journey push`） | REST API PATCH |
|---|---|---|
| 接続先 `connection`、`all_columns`、列の選択とマスキング | ✔ | ✔ |
| スケジュール / `run_after_journey_refresh` / 通知 | ✔ | ✔ |
| `connector_config`（Engage のワークスペース・AOC） | ✔ | ✔ |
| ビヘイビア列の出力 `behaviors:`（最大4テーブル） | ✔ | ✔ |
| **列名の変更**（`email_raw` を `email` として出力） | ❌（列は名前 + `visibility` のみ） | ✔ |
| **ストリングビルダー**（固定文字列・クーポンコード） | ❌ | ✔ |

YAML で書けないものだけ API で設定する。API は不正な値も受け付けることがあるので、**必ずテストジャーニーで先に実行**する（journey-update-safety.md）。

## 2. 準備（推測しない）

```bash
tdx connection list                              # コネクション名と type
tdx connection schema treasure_engage_v1         # connector_config のキー
tdx engage always-on-campaigns --workspace "<ws>"
tdx engage always-on-campaign show "<AOC名>" --workspace "<ws>"   # AOC ID
tdx engage workspace show "<ws>" --full --json   # workspace ID
```

## 3. YAML（ジャーニーの `activations:` はキー → 定義のマップ）

```yaml
activations:
  welcome-stage1:                            # ステップの with.activation から参照するキー
    name: CJO Welcome Stage1 Mail
    connection: <tdx connection list の Engage V1 コネクション名>
    all_columns: false
    columns:
      - email                                # Engage 側が受け取る宛先列が出力に含まれること
      - first_name
      - name: phone
        visibility: masked                   # clear | masked
    run_after_journey_refresh: true          # schedule とは排他
    connector_config:                        # treasure_engage_v1（snake_case）
      campaign_type: email                   # email | push
      campaign_model: always_on              # always_on | one_off | list
      workspace_id: "<Engage workspace UUID>"
      always_on_campaign_id: "<AOC UUID>"
      batch_size: 1000                       # 1-1000
      thread_count: 1                        # 1-10
      # json_columns: "items"                # JSON として扱う列（カンマ区切り）
    notification:
      notify_on: [onFailure]
      email_recipients: ["<通知先>"]
```

固定スケジュールにする場合（`run_after_journey_refresh` の代わり）:

```yaml
    schedule:
      type: daily                  # none | hourly | daily | weekly | monthly | cron | minutes_interval
      timezone: Asia/Tokyo
      start_at: "2026-11-10T11:00:00+09:00"
```

ビヘイビア列（購入履歴をメールに差し込む等）:

```yaml
    behaviors:
      - behavior_table: behavior_purchase_history   # tdx sg fields の名前
        join_strategy: Top-N                         # All | First | Last | Top-N
        join_row: 3
        formatting: rows                             # Top-N では必須
        order_by: [{ key: purchased_at, order: descending }]
        columns: [purchased_at, product_name, price] # order_by の key を含める
```

ビヘイビア出力のテーブルは、ステップのセグメントルール側でも Behavior 条件として参照されている必要がある。

## 4. push 時のアクティベーションの扱い

- `tdx journey push` は**アクティベーション名（`name`）で既存と照合**して更新し、無ければ作成する。名前を変えると新しいアクティベーションが作られる。
- 接続先（connection）を変えると新しい ID になり、Console 側が古い ID を参照し続けることがある（cjo-journey-tips）。
- push 後は必ず:

```bash
tdx journey activations "<journey>" --json > /tmp/acts.json
python3 scripts/latest_activations.py /tmp/acts.json     # 名前ごとの最新ID・重複・workspaceId・alwaysOnCampaignId
```

同名で複数あれば**IDが最大のものが最新**。

## 5. API PATCH（列名変更・ストリングビルダー）

対象: `PATCH /entities/journeys/{journeyId}/activations/{activationStepId}`（CDP API。ヘッダー `Content-Type: application/vnd.treasuredata.v1+json`）。
API のキーは **camelCase**（YAML の snake_case と違う）。

```json
{
  "type": "journeyActivationStep",
  "id": "<ACTIVATION_STEP_ID>",
  "attributes": {
    "activationParams": {
      "name": "CJO Welcome Stage1 Mail",
      "connectionId": "<CONNECTION_ID>",
      "allColumns": true,
      "columns": [
        { "column": "email", "source": { "column": "email_raw" } },
        { "column": "coupon_code", "source": { "string": "$1",
          "parameters": [ { "type": "String", "string": "<COUPON_CODE>" } ] } }
      ],
      "scheduleType": "daily",
      "scheduleOption": "11:00:00",
      "timezone": "Asia/Tokyo",
      "notifyOn": ["onFailure"],
      "emailRecipients": [<TD_USER_ID>],
      "connectorConfig": {
        "campaignType": "email",
        "workspaceId": "<WORKSPACE_ID>",
        "alwaysOnCampaignId": "<AOC_ID>",
        "jsonColumns": null,
        "batchSize": 1000,
        "threadCount": 1
      }
    }
  },
  "relationships": {}
}
```

手順（**テストジャーニー → 確認 → 本番**の順。本番に直接当てない）:

1. 現在値を取得してバックアップ: `python3 scripts/cdp_api.py get /entities/journeys/<J>/activations/<A> --out before.json`
2. `before.json` をもとに変更箇所だけ書き換えた `body.json` を作る（**現在の値を消さない**。`columns` は既存の列を全部残して追加する）
3. dry-run: `python3 scripts/cdp_api.py patch /entities/journeys/<J>/activations/<A> --body body.json`
4. 変更前後の差分を利用者に提示 → 承認
5. 実行: 同じコマンドに `--execute`
6. 再取得して確認 + Console で該当ジャーニーが開けること・設定表示が正しいことを確認
7. 異常があればバックアップ（`backups/`）の値で戻す PATCH を提案する

- `emailRecipients` は TD ユーザーID（`tdx users` で確認）。
- `scheduleOption` などの値の形式は `before.json` の既存値に合わせる。推測で新しいキーを足さない。
- 埋め込み値（クーポンコード等）は `cjo-engage-memo.yml` の `coupon_mapping` に記録する。

## 6. クーポン施策とステージの対応（確認ポイント）

| 施策の種別 | 対応するジャーニー分岐 |
|---|---|
| F0向け（F1転換） | 通常は対象外。新規登録・初回購入促進ジャーニーが別途必要か確認 |
| F1向け（F2転換） | 「F1（購入1回）」ステージ |
| F2以上（F3転換） | 「F2」「F3以上」ステージ |

設計書に「F0クーポン」があるのにジャーニーに該当ステージが無い場合は、勝手に追加せず利用者に確認する。
