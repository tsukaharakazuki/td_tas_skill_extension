# エンジン選択・Trinoメモリ診断

## 何を上限と比べるか

| 項目 | 意味 | 判断に使う証拠 |
| --- | --- | --- |
| 保存データ量 | ディスク上の圧縮サイズなど | テーブルメタデータ。メモリ必要量とは別 |
| スキャン量 | 条件適用前後に読むデータ | job / query plan / 実行統計 |
| 中間状態 | JOINのbuild側、集約のキー・配列、ソート等 | plan、カーディナリティ、演算子別統計 |
| query total / distributed memory | クエリ全体のメモリ | エラー全文、TDの契約・利用状況 |
| local / per-node memory | 特定workerでのメモリ | エラーのlocal / node表記、skew、演算子 |
| resource pool・並列度 | リソース割当と同時処理 | 実際のpool設定・キュー状況 |

**「100GBメモリ = 100GBテーブルまで処理可能」ではない。**
圧縮率、列数、文字列長、JOINの増幅、集約キー数、偏りで必要量が大きく変わる。
大きな入力のstreaming集計が通り、小さな入力の多対多JOINが失敗することもある。

### CPU / ユニットに関する運用前提

本Skillの作成依頼で、次の条件が利用者から提供されている。

> 契約CPU 1ユニットに対し10GB、10CPUなら100GB。

これを**利用者提供の契約・運用前提**として扱う。全TDアカウント共通の公開仕様、
CPU core数とTrino Unitの同義関係、各workerのメモリ量を示すものとは断定しない。

公式の利用状況ドキュメント[S6]は、Maximum Query Memory Limitを
「価格プランに基づく、クエリ単位の最大合計メモリ」と説明している。
確認した公開ページでは10GB / CPUの比率までは確認できなかった。
対象環境の契約、利用状況ダッシュボード、実際のエラーを優先して照合する。

計算例は`10 × 10GB = 100GB`という予算の目安に留める。
上限直前まで使える設計にせず余裕を持つ。単位表記GB / GiBもログに合わせる。
失敗時の使用量は必要量の下限にすぎず、「最大100GBで止まったから101GBあれば通る」とは言えない。
local errorは総メモリの増強だけでは解決しない場合がある。

## 選択の目安

| 特徴 | Trinoを優先 | Hive / 分割を検討 |
| --- | --- | --- |
| 探索・応答速度 | 小さな期間・必要列、反復的な分析 | 応答時間より大規模バッチの安定性 |
| JOIN | build側を十分小さくできる | 大きなJOIN状態、多対多、skew |
| 集約 | 単純なSUM / COUNT、絞ったキー | 大きなDISTINCT、巨大配列、巨大キー集合 |
| ソート | 小さなTop-N | 全件ソート、windowの巨大partition |
| 出力 | 少量取得、またはCTAS等 | 巨大なバッチ出力や段階処理 |
| 機能 | TD稼働版で関数が利用可能 | Hive専用機能が必要 |

Hiveも無制限ではない。メモリ、shuffle、skew、queue、同時実行、出力サイズの制約がある。
Hive変更は性能改善の保証ではなく、**SQL方言と出力契約の移行**を伴う。
一部工程だけHive、軽い最終集計はTrinoという分割も候補にする。

## メモリエラーの診断順

1. **エラーを分類する**: local / total / distributed、query stage数、result出力、queue待ちは別。
   エラー名は稼働版で異なるため、名前だけでなく全文を読む。
2. **スキャンを削る**: `TD_TIME_RANGE(time, start, end, timezone)`、必要列、早いfilter。
3. **JOINを調べる**: キー重複、NULL、左右件数、キーごとの最大件数、JOIN後件数。
4. **中間状態を削る**: JOIN前の重複排除・事前集約、不要列を捨てる。
5. **偏りを分離する**: NULL / 空文字 / 特定キーへ集中していないか。無条件にNULLを同一値へ埋めない。
6. **計算を分ける**: 中間テーブルを作る。WITHは一般に物理materializeの保証ではない。
7. **必要ならHiveへ**: [移行リファレンス](trino-to-hive.md)と[QA](validation.md)を適用する。
8. 契約増強・pool変更は管理者と相談する。設定値の変更で契約上限を回避しようとしない。

### JOIN増幅の例

```sql
-- 左右両方で同じキーが複数行なら、積の件数になる。
-- SELECTが読み取りでも本番全件では高負荷になり得る。対象期間を先に限定する。
SELECT customer_id, COUNT(*) AS n
FROM source_db.events
WHERE TD_TIME_RANGE(time, '2026-01-01', '2026-01-02', 'JST')
GROUP BY customer_id
HAVING COUNT(*) > 1
ORDER BY n DESC
LIMIT 20;
```

`LIMIT 20`は返す行数であり、その前のGROUP BY全体を20行にする指定ではない。
JOINキーの`CAST`、正規化、NULL処理で意図せず同一キーに潰していないかも確認する。

### よくある最適化の落とし穴

- `UNION → UNION ALL`: 重複を残してよい場合のみ。単なる高速化として置換しない。
- `COUNT(DISTINCT x) → approx_distinct(x)`: 近似を業務要件が許容する場合のみ。
- `ORDER BY ... LIMIT N`: Top-Nには有効だが、前段のJOINや集約の状態量は残り得る。
- CTAS: 大量結果の出力効率や段階処理に役立つが、JOIN・集約のメモリ不足を自動解決しない。
- JOINのBROADCAST: 小さいbuild側の複製に有効。大きい表の複製はlocal memoryを悪化させる。
- engine / pool / magic comment: 実行環境での対応を確認し、無条件のコピペを避ける。
- 分割処理: 境界の重複・欠落、windowやDISTINCTの跨ぎ、再実行・後片付けを設計する。

## 参照

- [S6] [Trino Utilization Dashboard](https://docs.treasure.ai/products/control-panel/utilization/accessing-your-presto-utilization-dashboard)
- [S7] [TD Trino Performance Tuning](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/trino/performance_tuning)
- [S8] [TD Trino Query FAQs](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/trino/query_faqs)

旧FAQのworker数値を現行全環境の固定上限として転記しない。
出典管理は[sources.md](sources.md)を参照する。
