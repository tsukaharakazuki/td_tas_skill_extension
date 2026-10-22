# 出典・適用範囲・更新方針

確認日: **2026-10-22（JST）**。作成: Treasure Work。

この資料は一次資料を参照した実務用の整理であり、公式仕様の代替ではない。
全関数の辞書や製品サポート契約でもない。実環境での動作はengine版・設定・入力型に依存する。

## 根拠の区別

| 種類 | 扱い |
| --- | --- |
| TD公式資料 | TD固有UDF、稼働engineの提供機能、契約 / 制限の説明を優先 |
| upstream Trino / Hive / Digdag | 言語・関数・operatorの一般仕様。TD稼働版への適用を別途確認 |
| 公式Skill | AI向けの整理として参考。一次仕様と矛盾する場合は一次仕様を優先 |
| 利用者提供の運用条件 | 特定環境の前提として明記。全アカウント共通仕様に一般化しない |
| 本Skillの設計上の推奨 | 意味互換や安全性のための手順。製品の強制仕様とは呼ばない |

## 主要な参照先

| ID | 参照先 | 適用範囲・注意 |
| --- | --- | --- |
| S1 | [Trino functions and operators — current](https://trino.io/docs/current/functions.html) | 最新upstream。TD稼働版での採用を保証しない |
| S2 | [TD Trino Function Reference](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/sql-reference/td_trino_function_reference) | TD固有関数の引数・戻り値 |
| S3 | [TD Trino 423](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/trino/trino-423) | TDの423向け差分。アカウント実版は別途確認 |
| S4 | [TD Presto 350 — archive](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/archives/presto-350) | 旧版の履歴。現行の推奨仕様と取り違えない |
| S5 | [TD Hive Function Reference](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/sql-reference/td_hive_function_reference) | TD HiveのUDF。upstream Hiveだけで判定しない |
| S6 | [Trino Utilization Dashboard](https://docs.treasure.ai/products/control-panel/utilization/accessing-your-presto-utilization-dashboard) | query単位の最大合計メモリと利用指標 |
| S7 | [TD Trino Performance Tuning](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/trino/performance_tuning) | pruning、JOIN、ソート、CTAS等 |
| S8 | [TD Trino Query FAQs](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/trino/query_faqs) | memory・出力診断。歴史的なworker数値を一般化しない |
| S9 | [Digdag td>](https://docs.digdag.io/operators/td.html) | engine名、出力指定、SQL挿入マーカー、ジョブ情報 |
| S10 | [Digdag operators](https://docs.digdag.io/operators.html) | operator一覧。TD hostedで全て利用可能とは限らない |
| S11 | [Digdag documentation](https://docs.digdag.io/) | Workflow定義、パラメータ、retry、session |
| S12 | [TD API — Workflow Commands](https://docs.treasure.ai/tools/cli-and-sdks/api#workflow-commands) | TD WorkflowのAPI / CLI。tdxのフラグとは区別 |
| S13 | [Apache Hive Language Manual UDF](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF) | Hive関数の一般仕様。TD版差分を照合 |
| S14 | [Official TD SQL Skills](https://github.com/treasure-data/td-skills/tree/main/sql-skills) | trino、hive、time-filtering、optimizer、migrationの構成を参考 |
| S15 | [tdx documentation](https://tdx.treasuredata.com/) | CLI構文はインストール版の`--help`でも確認 |
| S16 | [Supported query engine versions](https://docs.treasure.ai/requirements-and-limitations/supported-hive-and-presto-query-engine-versions) | 確認時の公開表はTrino423 / Hive2023.1。実アカウントのdefaultは未実測 |
| S17 | [TD Hive4](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/hive/hive4) | Hive2023.1の変更点、typed NULL、TD UDFのDB修飾、hash等 |

## 重要な記述の確認範囲

| 記述 | 根拠・確認範囲 |
| --- | --- |
| Trinoはqueryごとのメモリ上限を持つ | S6 / S7 / S8。localとtotalは別に診断 |
| 契約CPU 1ユニット = 10GB | **作成依頼での利用者提供条件**。確認した公開資料S6では比率を確認できない |
| `BIGINT → INT`は一般的な互換変換ではない | 両言語の型幅とCASTの意味。通常はBIGINTを維持 |
| `TRY_CAST(NULL ...)`と不正値のTRY_CASTは分ける | 定数NULLの型付けと、変換失敗の扱いは別問題 |
| JSONハッシュと区切り連結のハッシュは同義でない | 入力serializationが異なるため。アルゴリズム名だけでは互換性を言えない |
| WITHとマーカー位置はengineと出力方式次第 | S9および各engineのINSERT / CTAS構文。展開後SQLを確認 |
| ローカルvalidate / dry-runだけでSQL成功を保証しない | 各検証層の対象範囲による。実行QAを分ける設計 |
| configで開発条件を明示する | 実効値を監査しやすくする推奨。CLIパラメータが常に使えないという一般仕様ではない |

## バージョンの扱い

- Trino `current`、TD Trino 423、archiveのPresto 350を同じ版の仕様として混ぜない。
- `presto`というAPI / operator値はエンジン選択用の互換名の場合がある。
- Hiveのupstream最新版を、そのままTD Hiveの関数セットとみなさない。
- Digdagのupstream operator一覧とTD hosted環境の対応・制限を区別する。
- 既存Skillの性能倍率・既定値・広範な禁止事項は、そのまま普遍的事実として転記しない。
- 参照したupstream Skillの`main`とDigdag実装の`master`は更新されるURLで、今回commit SHAは固定していない。
  手元のSkill cache revisionやupstream masterを、TD deployed forkと同一とみなさない。
- Workflowの追加出典（operator実装、YAML仕様、CTAS / INSERT文法、hosted制約等）は
  [workflow.md](workflow.md)に、版別関数の追加出典は[trino-to-hive.md](trino-to-hive.md)に記載する。
- 関数が不明なら、その関数の公式ページ・対象版・最小fixtureを確認し、未確認なら明示する。

## 更新手順

1. 対象のTD engine / Digdag / tdx版、確認日、変更目的を記録する。
2. 関連するTD公式資料を先に確認し、必要なupstream版の仕様を照合する。
3. `references/`、SQLとWorkflow例、期待値、checkerのルールとテストを一緒に更新する。
4. ローカルcheckerテストとリンク整合性を確認する。
5. 実engineで検証した場合だけ、engine版・期間・期待値・結果・実行日を記録する。
6. 型・NULL・ID・日時・再実行が変わる修正は互換性変更として明記する。
7. 公式資料を読めなかった箇所は別のページから推測で埋めず、未確認として残す。

本資料では公式本文の大量転記を避け、手順・注意点・独自の小例を中心に記載している。
