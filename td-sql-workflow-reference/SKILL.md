---
name: td-sql-workflow-reference
description: Use when creating, reviewing, fixing, or optimizing Treasure Data SQL or Digdag Workflows in Treasure AI Studio or Treasure Work. Unify TD Trino and Hive dialects, TD UDFs, time partition pruning, memory-error diagnosis, Trino-to-Hive migration, td> output insertion and Workflow debugging. Trigger on TD SQL作成, SQLエラー, WFデバッグ, メモリ不足, TrinoからHiveへ移行, CAST, 正規表現エスケープ, DIGDAG_INSERT_LINE, create_table, insert_into, or engine変更. Read-only diagnosis by default with semantic regression checks before any execution. Also trigger for Treasure Data, TD, トレジャーデータ SQL and Treasure Workflow questions even when this skill is not named.
---

# TD SQL / Workflow Reference

Treasure DataのSQLと、それを実行するDigdagを**同じ処理の二つの層**として確認する。
新規作成、障害診断、Trino → Hive移行にこの入口を使い、必要な詳細だけ参照する。
回答は利用者の言語で行う。外部Skillのインストールを必須にしない。

## 1. 最初に実行層と処理契約を特定する

提示済みの情報を再質問せず、ファイル・エラー・ジョブログから次を埋める。
不足して修正方針が変わる情報だけ質問する。

- 目的、新規作成 / エラー修正 / 性能改善 / エンジン移行。
- 実行場所（Console / Studio / CLI / `td>`）、実ジョブのエンジンとバージョン。
- 元SQL、`.dig`、includeした設定、失敗タスク、job ID、エラー全文。
- 入出力DB・テーブル・スキーマ、型、主キー、NULL許容、期待する行の粒度。
- 対象期間・タイムゾーン・遅延到着、再実行時のappend / overwrite方針。
- メモリエラーでは、契約上限、実エラーの上限・使用量、pool、入力件数とJOIN増幅。

`presto`というAPI / Workflow上の名前だけで、旧Prestoバージョンと断定しない。
upstream Trinoの`current`にある関数を、TDの稼働版でも使えると決めつけない。
根拠と対応バージョンは[出典と更新方針](references/sources.md)を確認する。

## 2. 状況に応じて参照する

| 状況 | 読むファイル |
| --- | --- |
| SQLを新規作成、TD UDF、日時・timeパーティション | [SQL / UDF](references/sql-and-udfs.md) |
| メモリ不足、遅い、JOIN膨張、エンジン選択 | [エンジンとメモリ](references/engines-and-memory.md) |
| TrinoからHive、型、正規表現、JSON、ハッシュ | [移行リファレンス](references/trino-to-hive.md) |
| `.dig`、WITH、出力先、設定展開、リトライ | [Workflow](references/workflow.md) |
| エラー原因を切り分けたい | [診断プレイブック](references/debugging.md) |
| 移行後に結果が同じか確認 | [意味互換・QA](references/validation.md) |
| サンプルや使い方、ローカルチェック | [README](README.md)、[examples](examples/README.md) |

SQLの修正に加えて、`.dig`の`engine`、出力方式、テンプレート展開後SQLも確認する。

## 3. 新規作成の順序

1. 出力粒度、型、キー、NULL、期間、上書き・追記を先に決める。
2. スキーマがあれば読む。なければ読み取り専用のスキーマ確認を提案する。
3. [エンジンとメモリ](references/engines-and-memory.md)でTrino / Hive / 分割を選ぶ。
4. `time`列を直接使う半開区間の期間条件、必要列だけのSELECTを設計する。
5. 多対多JOIN、全件ソート、高カーディナリティ集約を点検する。
6. SQLとWorkflow出力指定を一緒に作る。参照テンプレートの識別子は置換必須と示す。
7. 静的確認 → 小さな境界データ → 少期間 → 本番相当の順で検証を提案する。

## 4. エラー診断・移行の順序

1. **最初に失敗した層**を特定する。YAML / 展開 / operator / SQL構文 / 型 / データ / メモリ / 出力を混同しない。
2. メモリ不足なら、入力縮小・事前集約・JOIN分割でTrinoを維持できるか確認する。
3. Hiveへ移行する場合は`engine`だけ変えず、[移行リファレンス](references/trino-to-hive.md)を全項目確認する。
4. 修正前後のSQL、`.dig`、出力スキーマを対にする。元ファイルを無断で上書きしない。
5. [意味互換・QA](references/validation.md)の境界データと集計比較を用意する。
6. 実行済み・未実行・未確認を明確に分ける。静的チェックを実機成功と表現しない。

### 優先して止める誤変換

- `CASE`と`CAST`は別。`AS`の型指定は主に`CAST(... AS type)`の話。
- Trinoの`VARCHAR`はHiveの`STRING`へ。**`BIGINT`は通常Hiveでも`BIGINT`のまま**。
- `TRY_CAST`の削除では不正値の扱いが変わり得る。`NULL`定数と汚れた入力を分ける。
- 正規表現はSQL文字列、YAML、JavaScriptテンプレートの層ごとに確認する。
- `TRY`を外したURL関数は、不正URLでの失敗 / NULLの挙動まで確認する。
- JSON配列のハッシュを区切り文字連結のハッシュに変えると、原則**別のID**になる。
- `WITH`と出力用DDL/DMLの位置はエンジンごとに違う。マーカーを一律に挿入しない。
- `LIMIT`だけではJOIN・集約の処理量やメモリを小さくできるとは限らない。

## 5. 安全な実行境界

- デフォルトはファイル確認・読み取り診断。顧客データや秘密を公開リポジトリへ載せない。
- Treasure Workでは現在のTDアカウント / profileを切り替えたり上書きしない。
- 認証切れはSettingsのAdd Account / Re-authenticateへ案内する。
- 利用可能なら`tdx ... --help`で実際の構文を確認し、存在しないフラグを作らない。
- `EXPLAIN`と`EXPLAIN ANALYZE`を区別する。後者はクエリを実行する。
- 読み取りSQLも費用・負荷を伴う。大量スキャンを勝手に実行しない。
- 作成・追記・上書き・削除・デプロイ・schedule変更は対象と影響を説明し確認する。
- Workflow実行 / 再試行はSQL以外のメール、HTTP、activationを含むと考える。
- `tdx wf run`は先に`--dry-run`し、タスクと外部送信・対象規模を説明して明示承認を待つ。
- dry-runで対象人数が分からなければ「不明」と伝え、読み取りで確定するまで実行しない。
- validate / dry-runはSQL実行成功、意味互換、全外部副作用の検出を保証しない。
- リトライを提案する前に、途中まで完了した出力と重複・上書き・外部送信を確認する。

## 6. 回答の形

```text
判定: [原因 / 採用エンジン / 追加確認が必要]
根拠: [ログ、スキーマ、公式出典、利用者から提供された運用条件]
修正: [SQLと必要な.dig / config差分]
注意: [NULL・型・日時・ID・出力互換への影響]
検証: [静的確認済 / 実機未実行 / 実行結果、比較手順]
次の一手: [最小で安全な確認、必要な承認]
```

### 例1: メモリ不足でHiveへ

**入力**: 「10CPU契約。100GBの上限エラーが出たのでHiveにして」

**対応**: 契約条件を利用者提供として記録し、エラーの上限と照合する。
100GBを「処理できるテーブルサイズ」とは呼ばない。JOIN・集約の状態量を確認する。
Hive SQLと`td.engine: hive`の両方を修正し、BIGINT維持、正規表現、NULL、ハッシュ、
WITH挿入位置を点検する。IDの生成規則が変わる場合は移行を止めて方針を確認する。

### 例2: WITH付きSQLがWorkflowだけ失敗

**入力**: 「Consoleでは成功。`create_table`のWorkflowではWITH付近で構文エラー」

**対応**: 実ジョブのエンジン、`create_table` / `insert_into`、展開後SQLを確認する。
[Workflow](references/workflow.md)のエンジン別挿入例で修正する。
DDLをSQLにも重ねて書いていないか確認し、YAML検証だけで解決済みとはしない。

### 例3: BIGINTとハッシュの置換

**入力**: 「`BIGINT → INT`、`SHA256(JSON...) → SHA2(CONCAT_WS...)`でよい？」

**対応**: そのままの互換変換ではないと説明する。BIGINTを維持する。
既存IDを維持するなら同一バイト列・同一hex表記を再現し、ゴールデンデータで一致を確認する。
新IDならバージョンを分け、既存JOINや重複除外への影響を利用者に確認する。
