# SQL / Workflow 診断プレイブック

## 最初に失敗した層を読む

| 症状・エラー例 | まず確認 | 修正・次の確認 |
| --- | --- | --- |
| `mapping values are not allowed here` | YAMLのindent、`: `、三項演算子、引用符 | YAMLを直す。SQL修正から始めない |
| `parameter ... not found` / 未展開`${...}` | `_export`、includeパス、タスクscope、綴り | 実際の有効設定を秘密を除いて表示 |
| pushは成功・jobなし | 起動 / schedule / 分岐 / task skip | deploymentと実行を分けて確認 |
| `mismatched input` / `cannot recognize input` | 実engine、展開後SQL、挿入DDL/DML | [Workflow](workflow.md)、[移行](trino-to-hive.md) |
| `WITH` / `INSERT` / `CREATE`付近で失敗 | 出力指定とマーカーの位置、二重DDL | engine別の最終SQLを確認 |
| `Unknown type` / 型が認識されない | HiveへのVARCHAR持ち込み等 | CASTの型、出力スキーマ |
| `Function ... not registered` / `Invalid function` | upstreamではなくTD稼働版の関数 | TD UDF表と版、関数引数型 |
| 不正cast / 数値format / overflow | 元値、TRY_CASTの削除、INT縮小 | 汚れた値を分離し、失敗数を集計 |
| `CASE` / COALESCE / UNIONの型不一致 | 全分岐・全SELECTの型、裸NULL | 共通の型へ明示CAST、DECIMAL桁を確認 |
| 正規表現が通るのに件数が違う | SQL / YAML / JSのエスケープ層 | `a.b`と`axb`のfixtureで意味確認 |
| URLやJSONで一部入力だけ失敗 | TRY除去、異常値、missing / NULL | 異常入力の契約を決める |
| local / query / total memory error | ログの上限・使用量、JOIN・集約・skew | [メモリ](engines-and-memory.md) |
| stage数過多・planner制約 | 多段WITH、CTE多重参照、UNION・サブクエリ | 中間表へ分割。メモリ増強と混同しない |
| queue / timeout | pool、同時実行、キュー待ち時間 | 構文エラーではない。安易に再試行を重ねない |
| 出力テーブルがない・列が違う | DB、出力指定、スキーマ、権限、途中失敗 | 確認前にDROPしない |
| 成功だが行数が倍増 | append、retry、JOIN重複、期間重複 | append / overwriteの契約と途中出力 |
| 401 / 403 | 接続アカウント、期限、対象権限 | Treasure Work Settingsで再認証。profileを勝手に変えない |

エラー文は例であり、稼働版で表記が変わる。完全一致検索だけに依存しない。

## Consoleで成功、Workflowで失敗

1. 同じengineか。`td>`ではTrino系の指定名が`presto`の場合がある。
2. 本当に同じSQLか。テンプレート展開、include、database、timezoneを比較する。
3. `create_table` / `insert_into`で加わるSQLと挿入位置を確認する。
4. SQLファイルにもCREATE / INSERTを書いて二重にしていないか。
5. 一時表、前タスクの実行順、parallelでの競合がないか。
6. ジョブログに出た最終SQLの構文位置と、元SQLの行番号のずれを考慮する。
7. 権限・pool・session・時間条件を確認する。

マーカーは一般的なSQLの特殊構文ではなく、`td>`のSQL挿入位置指定用コメント。
Consoleでは単なるコメントでも、Workflowでは実際のSQL構造を変える。

## 最小再現に落とす

- job ID・task名・元ログを保全し、機密を伏せたSQLを別ファイルにする。
- 同じ引数型の定数 / fixtureで、失敗する式だけを実行する。
- 大規模JOIN全体を何度も実行せず、各入力の型・件数・キー重複を確認する。
- 期間縮小は入力側で行う。最後のLIMITだけで小試験にしたつもりにならない。
- 構文修正の後に意味確認を行う。`TRY`を除去して通ることだけを合格基準にしない。
- 修正案には「どのデータで失敗 / NULL / 値の変更があり得るか」を添える。

## 障害対応の記録

```text
症状: [いつ / どのタスク / 影響範囲]
失敗した層: [YAML / 展開 / operator / SQL / data / memory / output]
証拠: [機密除去したログ、engine、出力SQL、型]
原因: [確定 / 仮説と未確認情報]
修正: [最小差分、engine / .dig / SQL / config]
互換性: [NULL / 件数 / precision / ID / timezone / 再実行]
確認結果: [ローカルのみ / 少期間実行済 / 本番相当済]
再開判断: [途中出力と外部副作用、必要な承認]
```

リトライ・再開は元処理がどこまで完了したかを確認してから。
メールやactivationの存在が不明なら、外部副作用がないとは扱わない。
