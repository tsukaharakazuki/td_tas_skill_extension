# セグメント条件リファレンス（ジャーニー埋め込み / 子セグメント共通）

出典: td-tdx-segment / td-tdx-validate-segment / cjo-journey-tips を統合。

## 1. 作る前に必ず実データを見る

```bash
tdx sg use "<親セグメント名>"
tdx ps desc "<親セグメント名>" -o /tmp/ps_schema.json   # 出力DB・customers・behavior_* と型
tdx sg fields                                             # セグメントで使える attribute / behavior
tdx query "SELECT <col>, COUNT(*) FROM cdp_audience_<ps_id>.customers GROUP BY 1 ORDER BY 2 DESC LIMIT 20"
```

- 値の表記（`"true"` / `true` / `1`、全角・半角、大文字小文字）を実データで確認してから書く。
- NULL率が高い列は「IS NULLを含めるか」を利用者に確認する。
- 親セグメントIDはURLから推測しない。`tdx ps list` にIDは出ないので、名前を利用者に聞く。

## 2. YAML 基本形

```yaml
rule:
  type: And            # And | Or
  conditions:
    - type: Value
      attribute: country
      operator: { type: In, value: ["JP"] }
    - type: Value
      attribute: email_opt_in
      operator: { type: Equal, value: "true" }
```

## 3. 演算子（18種類。これ以外は INVALID_OPERATOR_TYPE）

| 分類 | type | 必須 |
|---|---|---|
| 比較 | `Equal` `NotEqual` `Greater` `GreaterEqual` `Less` `LessEqual` | `value` |
| 範囲 | `Between` | `min` / `max` の片方以上 |
| 集合 | `In` `NotIn` | `value`（配列） |
| 文字列 | `Contain` `StartWith` `EndWith` | `value`（文字列配列） |
| 正規表現 | `Regexp` | `value`（文字列） |
| NULL | `IsNull` | なし（NOT NULL は `not: true`） |
| 時間 | `TimeWithinPast` `TimeWithinNext` | `value` + `unit` |
| 時間 | `TimeRange` | `duration` + `from` |
| 時間 | `TimeToday` | なし |

- 否定は全演算子で `not: true`。
- 単位は単数形のみ: `year | quarter | month | week | day | hour | minute | second`（`days` は誤り）。
- 同一属性の OR は `In` を使う（ネストすると `NESTED_CONDITION_GROUP` 警告。実行は正しいがConsoleのSQLプレビュー表示が崩れる）。

```yaml
# TimeRange: 1か月前を起点に7日間
operator:
  type: TimeRange
  duration: { day: 7 }
  from: { last: 1, unit: month }
```

## 4. ビヘイビア条件

```yaml
- type: Value
  attribute: ""                       # ビヘイビア集計では空文字
  source: behavior_purchase_history   # tdx sg fields の behavior 名（behavior_ 接頭辞）
  aggregation:
    type: Sum                         # Count | Sum | Average | Min | Max
    column: order_total               # Count 以外で必須
  operator: { type: Greater, value: 500 }
  timeWindow: { duration: 90, unit: day }
  filter:                             # source を使うときは必須
    type: And
    conditions:
      - type: Column                  # filter 内は Column + column（Value + attribute ではない）
        column: category
        operator: { type: Equal, value: "Electronics" }
```

`type: Behavior` はローカル validate を通ってもサーバーで落ちることがある。`type: Value` + `source` を使う。

## 5. 「未購買」「経験なし」の落とし穴（cjo-journey-tips）

RFMや購買ビヘイビアには**実績のある人のレコードしか無い**ことが多い。`frequency_all = 0` は誰も抽出しない。

正しい書き方: 「購買1回以上のレコード数 < 1」

```yaml
- type: Value
  attribute: ""
  source: behavior_rfm
  aggregation: { type: Count }
  operator: { type: Less, value: 1 }          # COUNT < 1
  filter:
    type: And
    conditions:
      - type: Column
        column: frequency_all
        operator: { type: GreaterEqual, value: 1 }
```

作成前に利用者へ確認する: 「対象テーブルには購買者しかいない可能性が高いので、"レコードがある人を除外（COUNT < 1）" で実装してよいですか？」

## 6. 設計前チェックリスト（設計書・Excelから起こす時）

1. F0 / 未購買 / 初回購入促進 → 上記 COUNT < 1 方式でよいか
2. 「会員登録からN日」→ ビヘイビアで判定か、属性（例: `registerdatetime_duration`）で判定か
3. 「購買N回以上」「Fx転換」→ ジャーニーの各ステージ（F1向け / F2向け）とクーポン施策側セグメントの対応表
4. 除外ロジック → 下記 7. の方針で実装方法を決める

## 7. 除外（Exclude）の実装方針

| 優先 | 方法 | 用途 |
|---|---|---|
| 1 | ルール内で表現（`not: true`、`NotIn`、COUNT < 1） | 埋め込みセグメント・子セグメント共通。最も安全 |
| 2 | `type: exclude` + `segment: "<既存セグメント名>"` | サーバー上に既に存在するセグメントを除外 |
| 3 | 決定分岐の `excluded: true` | 「それ以外」ブランチ（catch-all）。セグメント不要 |

- cjo-journey-tips には「YAMLの `excluded: true` が反映されない報告がある」とある。push後に `tdx journey pull` と Console で分岐条件を必ず目視確認し、反映されていなければ優先1の書き方へ置き換える。
- **raw API でセグメントを PUT/PATCH しない**（td-tdx-segment の安全規則）。一覧取得や entities 読み取りでは rule が空で返ることがあり、そのまま書き戻すと**ルールが消える**。
  - 子セグメントの変更は `tdx sg push`、フォルダ移動は `tdx sg move`。
  - ジャーニー埋め込みセグメントは journey YAML を直して `tdx journey push`。
  - どうしても API が必要な場合（cjo-journey-tips の PUT `/audiences/{audienceId}/segments/{segmentId}`）は、単体GETで rule が空でないことを確認 → バックアップ保存 → 差分を利用者に提示 → 明示承認の後に限る。`scripts/cdp_api.py` はこの手順（GETバックアップ + dry-run既定）を強制する。

## 8. 子セグメントの作成・更新（ジャーニー外で使う場合）

1件ずつ:

```bash
tdx sg validate "<file>"
tdx sg sql --path "<file>" | tdx query -     # 件数 > 0 を確認（tdx.json のある pull 済みフォルダ内で）
# preview_segment で利用者に確認
tdx sg push --dry-run "<file>"
tdx sg push -y "<file>"
```

- `tdx sg push --delete` は使わない（ローカルに無いセグメントを削除する）。
- 名前検索は `tdx sg list "<pattern>" -r`。同名が複数あれば利用者に選んでもらう。
- push後: `https://console.treasuredata.com/app/audiences/<parent_id>/segments/<segment_id>` を提示。

## 9. エラーコード早見表

| Code | 原因 → 対処 |
|---|---|
| `MISSING_NAME` | `name:` を追加 |
| `INVALID_RULE_TYPE` | `And` / `Or` の綴り |
| `MISSING_CONDITIONS` | `conditions:` 配列が無い |
| `EMPTY_ATTRIBUTE` | 属性名を入れる（ビヘイビアは `""`） |
| `INVALID_OPERATOR_TYPE` | 上表18種のどれか |
| `MISSING_OPERATOR_VALUE` | `value:` を追加 |
| `MISSING_BETWEEN_BOUNDS` | `min` / `max` |
| `MISSING_TIME_UNIT` | `unit: day`（単数形） |
| `INVALID_ARRAY_MATCHING` | `any` / `all` / `{atLeast: N}` / `{atMost: N}` / `{exactly: N}` |
| `MISSING_SEGMENT_REFERENCE` | include/exclude に `segment:` |
| `NESTED_CONDITION_GROUP` | 警告のみ。同一属性なら `In` に |
| `SEGMENT_SCHEMA_ERROR` | filter 内で `column` を使っているか等 |

ローカル `validate` は参照先セグメントの存在・フィールドの有無・ビヘイビアのスキーマを検査しない。必ず `push --dry-run` も通す。
