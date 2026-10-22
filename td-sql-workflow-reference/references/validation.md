# 意味互換と検証

構文が通ること、Workflowが完了すること、業務上同じ結果になることは別の検証である。
エンジンを替えた場合は、SQLだけでなく出力スキーマと再実行動作も確認する。

## 検証の階段

| 段階 | 確認するもの | 確認できないもの |
| --- | --- | --- |
| ローカルrisk checker | 既知の方言・マーカーの疑わしい記述 | SQL構文の完全性、UDFの有無、型、意味、展開後SQL |
| YAML / Workflow validate | 対応範囲の構造・設定 | 稼働engineでのSQL実行成功、データ品質 |
| dry-run | 対応範囲の実行計画・操作予定 | 全副作用の検出、対象人数の完全把握、SQL成功 |
| 境界fixture実行 | 少数の型・関数・NULL挙動 | 本番カーディナリティ・skewでの性能 |
| 少期間・隔離出力 | 実スキーマ、入出力、期間境界 | 本番全量のメモリ・時間 |
| 本番相当QA | 意味、件数、性能、再実行 | 将来のデータ変化への無条件保証 |

このリポジトリのユニットテストは**ローカルcheckerのテスト**。
TD Trino / Hiveの実行試験や認証済み環境での検証ではない。

## 最小の境界データ

| 分類 | 最低限の値 | 見る差分 |
| --- | --- | --- |
| NULL・文字列 | NULL、空文字、空白、`'null'`、`'001'` | NULLと空の混同、trim、暗黙cast |
| 整数 | 0、負数、2147483647、2147483648、BIGINT境界 | INT縮小、overflow、不正値 |
| DECIMAL | 小数端数、負値、桁上限付近 | precision / scale、丸め・切捨て |
| 不正cast | `'abc'`、`''`、指数表記、桁あふれ | TRY_CASTとCASTの違い |
| 正規表現 | `a.b`、`axb`、`a\\b`、Unicode | dotやbackslashのliteral性 |
| URL | 正常、相対、NULL、不正、port、IDN | host、例外、NULL |
| JSON | NULL、JSON null、配列内NULL、空配列、quote、tab、改行 | parser、型、escaping |
| 配列 | 空、NULL、重複、順序、配列内NULL | explode行数、collect順・NULL脱落 |
| JOIN | 左右重複、NULL、空キー、片側のみ | 行数増幅、inner / left意味 |
| 日時 | 開始直前・開始一致・終了直前・終了一致 | 半開区間、UTC / JST |
| 日時（該当時） | DST切替、月末、閏日、epoch秒 / ms | calendar計算、境界ずれ |
| ハッシュ | 上記文字列の組合せ、区切り文字入り、列入替 | byte列・encoding・hex一致 |

実行用の小例は[examples](../examples/README.md)を参照する。
汚れた値で例外になり得る試験は、正常系の試験から分離する。

## 出力比較の契約

1. **入力固定**: 同じsnapshot / 同じ期間 / 同じtimezoneで比較する。
   更新中の表に別時刻でクエリして差をengine差と断定しない。
2. **型比較**: 列名・型・precision / scale・NULL許容を一覧化する。
   TD保存時の型マッピングとSQL評価時の型を区別する。
3. **粒度比較**: 主キーごとの行数、重複件数、全件数を比べる。
4. **NULL比較**: 各列のNULL数・空文字数、parse / cast失敗数を比べる。
5. **値比較**: 金額合計、min / max、日別・キー別集計を比べる。
6. **行比較**: NULL-safeに比較する。Trinoの`IS NOT DISTINCT FROM`とHiveの`<=>`は別構文。
   `NULL = NULL`は一致判定にならない。キー自体がNULLの行も別途検証する。
7. **重複比較**: 集合差分だけでは多重度が消える。必要なら全列ごとの件数も比較する。
8. **数値許容**: 浮動小数だけは事前合意した絶対・相対誤差。金額を安易に近似しない。
9. **順序比較**: ORDER BYがない行順・配列集約順に依存しない。必要なら順序仕様を作る。
10. **再実行**: 同一sessionで2回実行した際の重複、上書き、部分失敗を検証する。

### 集計比較の雛形（両エンジンの基本構文）

```sql
-- old_result / new_resultは同じ入力・期間で作った隔離出力へ置換する。
SELECT 'old' AS version,
       COUNT(*) AS rows_total,
       COUNT(DISTINCT customer_id) AS customers,
       SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_keys,
       SUM(amount) AS total_amount
FROM qa_db.old_result
UNION ALL
SELECT 'new' AS version,
       COUNT(*) AS rows_total,
       COUNT(DISTINCT customer_id) AS customers,
       SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_keys,
       SUM(amount) AS total_amount
FROM qa_db.new_result;
```

大規模なCOUNT DISTINCTもメモリを使う。期間やキーを分割する。
この集計が一致しても行の意味互換を証明したことにはならない。

## ハッシュの特別ルール

- 既存のIDを維持するなら、入力列・順番・型・NULL・Unicode・serialization・encoding・
  hash algorithm・hex大小文字を固定し、全fixtureを同じ期待値と比較する。
- `JSON_FORMAT(ARRAY...)`と`CONCAT_WS`は別のserialization。
  同じSHA-256系でも入力が違えば一致しない。
- ハッシュ関数の衝突確率だけでなく、**ハッシュ前の連結衝突**をテストする。
- 新しい生成規則を採用する場合は`id_v2`等に分け、既存JOIN・履歴・activationとの接続を承認する。
- 実機の一致を確認するまで「互換」と言わない。サンプルの数件一致も一般証明ではない。

## 実行結果の記録テンプレート

```text
対象 / 実行日時:
TD region / account識別（秘密を除く）:
engine / version / pool:
入力snapshot / 対象期間 / timezone:
元SQLと新SQLのrevision:
出力先と書込方式:
確認した型 / 件数 / NULL / 値 / ID:
所要時間 / peak memory / scan:
未確認項目:
承認者と次の段階:
```

ログ・サンプルは秘密と個人情報を除いて保存する。job ID等の実顧客情報を本Skillへコミットしない。
