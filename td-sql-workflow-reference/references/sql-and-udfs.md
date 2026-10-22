# SQL新規作成・TD UDF・日時

## 1. 対応版と関数を確認する

確認日2026-10-22の[公式対応表](https://docs.treasure.ai/requirements-and-limitations/supported-hive-and-presto-query-engine-versions)は、
**Trino 423 / Hive 2023.1（Apache Hive 4ベース）**を掲載している。
これは対象アカウントの実行engine / defaultを実測したものではない。

- upstream Trinoの`current`は、TDの423より新しい関数を含み得る。
- [Trino423ページ](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/trino/trino-423)の
  旧defaultに関する記述と、現行対応表を混ぜて「全アカウントでdefaultは350」と断定しない。
- Presto350のarchiveは旧SQL調査に使う。現行の提供保証とみなさない。
- `td>`のengine指定は`presto` / `hive`。[Workflow](workflow.md)を併読する。
- native関数、TD固有UDF、追加ライブラリ / 独自登録関数を分ける。

## 2. 先に定義するSQLの契約

- 行の粒度（顧客 / 注文 / 明細 / session / 日次）とキー。
- IDの文字列 / 数値、先頭ゼロ、大小文字、trim・正規化の要否。
- 金額の型と小数桁、NULL / 空文字 / 不正値の扱い。
- 同時刻データのtie-breaker、重複排除の単位。
- 対象期間、time列と業務日時の違い、遅延到着、timezone。
- append / replace、再実行、履歴の保持。

スキーマが不明なら、型を想像して書き進めず、利用可能な読み取り専用describeで確認する。
実データのsampleは必要最小限・機密除去して扱う。

## 3. TD時間関数の要点

TDの通常の`time`は**Unix秒**。TIMESTAMP型やUnixミリ秒と同じではない [S2, S5]。

| 関数 | 入力と出力・役割 | 注意 |
| --- | --- | --- |
| `TD_TIME_RANGE(time,start,end[,zone])` | Unix秒を期間判定 | **開始含む・終了含まない**。zone省略時はUTC |
| `TD_INTERVAL(time,range[,zone])` | scheduled基準の相対・calendar期間 | 第1引数は行のtime。zone省略時はUTC |
| `TD_TIME_PARSE(text[,zone])` | 文字列 → Unix秒 | zone省略時UTC。不正文字列はNULL |
| `TD_TIME_FORMAT(time,format[,zone])` | Unix秒 → 表示文字列 | format規則とzoneを明示 |
| `TD_TIME_STRING(time,precision[,zone])` | Trino向けのprecision別時刻文字列 | precisionと`!`の意味は下記 |
| `TD_DATE_TRUNC(unit,time[,zone])` | 単位境界へ切ったUnix秒 | native `date_trunc`のtimestamp型とは別 |
| `TD_SCHEDULED_TIME()` | scheduled / job-issue基準のUnix秒 | 実開始時刻・wall clock nowとは異なり得る |

境界文字列にtimezoneを埋めた場合、そのzoneが既定zone引数より優先される。
`TD_TIME_RANGE`のNULL startはepoch zero、NULL / 省略endは上限なしという契約にも注意する。
意図せず全期間を読むNULL境界を生成しない。

### 月全体の半開区間

```sql
-- 1月31日も含めるには、終了を2月1日とする。
WHERE TD_TIME_RANGE(time, '2026-01-01', '2026-02-01', 'Asia/Tokyo')
```

`BETWEEN`の両端包含と同じではない。
開始一致・終了一致を含むfixtureで確認する。epochミリ秒を渡す場合は、桁と元schemaを確認してから秒へ変換する。

### 相対期間と再実行

```sql
WHERE TD_INTERVAL(time, '-1d', 'Asia/Tokyo')
```

これはscheduled基準・単位境界を使う期間であり、常に直近86400秒を表すわけではない。
`M`（月）と`m`（分）を区別する。offset / 固定anchorを使う場合は公式のinterval文法を確認し、
実際の開始・終了時刻を試験する。retry / backfillは同じsessionで同じ期間になるようにする。
`SELECT TD_SCHEDULED_TIME()`を置くだけで全クエリの基準が確立する等の未確認の儀式を要求しない。

### TD_TIME_STRINGのprecision

例えば同じ時刻をAsia/Tokyoで日単位に表示する場合:

```sql
TD_TIME_STRING(time, 'd',  'Asia/Tokyo') -- 日初へ切り、完全な日時とoffsetを表示
TD_TIME_STRING(time, 'd!', 'Asia/Tokyo') -- yyyy-MM-ddの文字列
TD_TIME_STRING(time, 'M!', 'Asia/Tokyo') -- yyyy-MMの文字列
TD_TIME_STRING(time, 's!', 'Asia/Tokyo') -- 秒まで、offsetなしの文字列
```

- **`!`は選んだprecisionで表示を短くする**。単にtimezoneを除く記号と説明しない。
- `M`は月、`m`は分。返り値はDATE / TIMESTAMPではなく文字列。
- Hiveで`d!`に相当する日付表示なら`TD_TIME_FORMAT(time,'yyyy-MM-dd','Asia/Tokyo')`を候補にする。
  全unit / `!`なし / calendar切捨てを同じformatterへ一律変換しない。
- Hive nativeの`unix_timestamp`、Trinoの`from_unixtime`等へ置換する場合、返り型とtimezoneを比較する。

## 4. timeパーティションを使う

```sql
SELECT customer_id,
       SUM(CAST(amount AS DECIMAL(18, 2))) AS total_amount
FROM source_db.orders
WHERE TD_TIME_RANGE(time, '2026-01-01', '2026-02-01', 'Asia/Tokyo')
GROUP BY customer_id;
```

テーブルと列は例。元データが注文明細なら、注文合計を行ごとにSUMしない。
金額の不正値・NULLと、SUMの結果型も確認する。

- `time`を直接期間条件へ使い、必要な列だけ読む。
- 業務イベント日時と取り込みtimeが違う場合、正しい業務条件と、遅延到着を含めたtime scan範囲を分ける。
- `WHERE TD_TIME_FORMAT(time,...) = '...'`や業務日付列だけの条件で、time pruningを保証しない。
- boundary内の除算、subquery、非定数式はpruningを妨げ得る [S7]。planとscanを確認する。
- 必要なら日時の表示・GROUP BYと、WHEREのtime条件を分ける。
- 小試験は**入力側の期間・件数**を縮小する。最後のLIMITだけに頼らない。

## 5. その他のTD UDFを選ぶ

| 用途 | 文書化された候補 | 確認する点 |
| --- | --- | --- |
| IPの国判定 | `TD_IP_TO_COUNTRY_CODE(ip)` | IP形式、NULL、不正値、GeoIP版。HiveとTrinoで結果が異なり得る |
| User-Agent解析 | Trino `TD_PARSE_AGENT(ua)` | MAPキーの有無。欠損キーは`element_at`で安全に参照 |
| session境界 | Trino `TD_SESSIONIZE_WINDOW(time,timeout)` | 秒timeout、ユーザー単位PARTITION、時刻順、同時刻、遅延到着 |
| URL encode / decode | `TD_URL_ENCODE` / `TD_URL_DECODE` | engine別signature、不正escape、二重decode。全例外がNULLになるとは保証しない |
| URL host / path | native Trino `url_extract_*`、Hive `parse_url` | 両engineで同じ関数名とは限らない |

```sql
-- Trino: timeoutの単位は秒。出力型や境界挙動は対象版で試験する。
TD_SESSIONIZE_WINDOW(time, 1800)
  OVER (PARTITION BY customer_id ORDER BY time)

-- Trino: key名は実際の返却MAPに合わせる。
element_at(TD_PARSE_AGENT(user_agent), 'ua_family')
```

`TD_SESSIONIZE`はTrinoリファレンスでdeprecatedとして言及され、window版が推奨されている。
別engineへの移行時は旧関数との引数・順序・session ID互換を独立に確認する。
GeoIPデータベース更新により、SQLを変えなくてもIP判定が変わる場合がある。

未知のUDFを扱う場合:

1. [TD Trino UDF](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/sql-reference/td_trino_function_reference)または
   [TD Hive UDF](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/sql-reference/td_hive_function_reference)を読む。
2. native関数なら対象版のTrino / Hiveの資料を読む。TD UDF表にないことだけで未実装と断定しない。
3. 引数順・型・戻り型、NULL / 不正値、timezone、版の差を記録する。
4. 定数fixtureで最小確認し、初めて実schemaの少期間へ広げる。
5. 見つからなければ未確認と伝える。存在を推測した関数を作らない。

## 6. 新規SQLでも防ぐ意味の誤り

- `COUNT(*)`と`COUNT(col)`はNULL行の扱いが違う。
- 全件NULLや空入力のSUM結果を、根拠なく0とみなさない。
- `NOT IN`の相手にNULLがある場合の三値論理を確認する。NOT EXISTS等の要件を検討する。
- LEFT JOINした右表の条件をWHEREへ移すと、左側のみの行が落ち得る。
- JOIN前後のキー重複、粒度、行数増幅を確認する。DISTINCTを最後に足して原因を隠さない。
- `ROW_NUMBER`で最新1行を選ぶ場合、同時刻の一意なtie-breakerを指定する。
- 並列実行の行順や、ORDER BYなしの配列集約順に業務ロジックを依存させない。
- exactからapprox、UNIONからUNION ALLへの置換は、性能改善ではなく要件変更も含む。

性能は[エンジンとメモリ](engines-and-memory.md)、型と関数の差分は[移行](trino-to-hive.md)、
検証は[QA](validation.md)、出典の範囲は[sources.md](sources.md)を参照する。
