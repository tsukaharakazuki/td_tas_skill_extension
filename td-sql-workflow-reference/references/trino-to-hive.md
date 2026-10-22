# Trino → Hive 移行リファレンス

**文字列置換ではなく、型・NULL・順序・出力契約の移行**として扱う。
`engine`変更とSQL変更を一組にし、[Workflow出力位置](workflow.md)と[QA](validation.md)も確認する。
TDの稼働版を優先する。以下は文書に基づく例であり、この作成作業でTD実機には送信していない。

## 1. 型 / CAST / CASE

| Trino | Hiveでの候補 | 条件・リスク |
| --- | --- | --- |
| `CAST(x AS VARCHAR)` | `CAST(x AS STRING)` | 長さ制約・出力schemaも確認。HiveのVARCHAR(n)という型の存在と、TDで使う方針は別 |
| `CAST(x AS BIGINT)` | **`CAST(x AS BIGINT)`** | INTへ縮小しない。32-bitと64-bitの範囲差 |
| `INTEGER` / `INT` | `INT` | 値域が同じでも元値・overflow・小数からの丸めを試験 |
| `DECIMAL(p,s)` | `DECIMAL(p,s)` | 中間計算・SUM等の結果型、precision / scaleも比較 |
| `TRY_CAST(NULL AS DECIMAL)` | `CAST(NULL AS DECIMAL(p,s))` | 型付けが目的の定数NULL。必要なp,sを明示 |
| `TRY_CAST(raw AS BIGINT)` | `CAST(raw AS BIGINT)`を候補として試験 | 不正文字、空文字、overflowのNULL / 例外挙動を確認 |
| `DOUBLE` | `DOUBLE` | 浮動小数。金額やIDへ安易に使わない |
| `VARBINARY` | `BINARY`を候補として試験 | encodingと関数の受入型を確認 |
| `BOOLEAN` | `BOOLEAN` | NULLを含む三値論理と暗黙castを確認 |
| `ARRAY(T)` / `MAP(K,V)` / `ROW(...)` | `ARRAY<T>` / `MAP<K,V>` / `STRUCT<...>` | 複合型構文、要素型、NULL、serializationを比較 |

CASTが型変換、CASEが分岐。`AS`の後の型を変える話と、`CASE WHEN`の話を分ける。
CASE / IF / COALESCE / UNIONの全分岐を同じ型へ寄せる。裸NULLはHive4でVOID関連エラーになる場合がある。

```sql
-- Trino
CASE WHEN is_member THEN CAST(member_id AS VARCHAR)
     ELSE CAST(NULL AS VARCHAR) END

-- Hive
CASE WHEN is_member THEN CAST(member_id AS STRING)
     ELSE CAST(NULL AS STRING) END
```

- `2147483648`はBIGINTで扱え、signed INTの上限`2147483647`を超える。
- `DECIMAL`を無指定で使わない。Trinoのbare DECIMALは38桁・scale 0で、他engineの既定を同じとみなさない。
- `TRY_CAST`はcast失敗をNULLにするもの。**引数のUDF評価で起きる全例外を捕捉する保証ではない**。
- HiveのCASTは文書上、変換失敗でNULLを返すが、全データ型 / 算術 / UDFの挙動まで同一とは限らない。
- 正規表現で「数字だけ」を確認しても桁あふれは防げない。
- `WHERE guard AND dangerous_expression`の評価順へ依存しない。安全な入力の隔離、遅延評価するCASE等、
  対象型の値域を含む契約を設計する。未検証のガードをTRYの完全代替と呼ばない。

## 2. 正規表現のエスケープ

**外部SQLファイル中の文字数**を示す。Trinoは1本、Hiveは2本のbackslash。

```sql
-- Trino: regexへbackslash-dotを渡す
SELECT regexp_like('a.b', '\.'), regexp_like('axb', '\.');
-- 期待: true, false

-- Hive: SQL文字列のescape層を一段多く通す
SELECT 'a.b' RLIKE '\\.', 'axb' RLIKE '\\.';
-- 期待: true, false
```

| 意図 | TrinoのSQL literal | HiveのSQL literal |
| --- | --- | --- |
| literal dot | `'\.'` | `'\\.'` |
| digit class | `'\d+'` | `'\\d+'` |
| whitespace class | `'\s+'` | `'\\s+'` |

- `regexp_like(s,p)` → `s RLIKE p`が基本候補。両者とも部分一致なので、全体一致ならanchorを設計する。
- `regexp_extract`のgroup index、マッチなし、NULL、replacement `$1`等は関数ごとに試験する。
- Trinoのnamed replacement `${name}`とDigdagの`${...}`展開は衝突し得る。block scalarでもDigdag展開は無効にならない。
- `.sql` / YAML block `|`はYAMLのbackslash変換を避けるが、SQLとregexの層は残る。
- double-quoted YAML、JavaScript式、JSON transportを重ねたら追加のescape層を確認する。
  画面に表示されたJSONのslash数をSQLへそのまま貼らない。
- 全backslashの一括倍増は、既にescape済みのliteral、置換文字列、JSONを壊す。

## 3. URLとTRY

| Trino | Hiveの推奨候補 | 検証点 |
| --- | --- | --- |
| `TRY(url_extract_host(u))` | `parse_url(u, 'HOST')` | 不正URL、相対URL、NULL、port、IDN、例外 / NULL |
| `url_extract_path(u)` | `parse_url(u, 'PATH')` | encoding、空path、reserved文字 |
| URL decode | 文書化された`TD_URL_DECODE`等 | 不正percent escapeの挙動、二重decode |

**Hiveの`url_extract_host`利用可否は、今回確認した公式資料では裏付けられていない。**
独自UDFが登録されている可能性を否定するものではないが、可搬な標準名と扱わない。
Hive標準の`parse_url`を優先し、実engineでfixtureを確認する。

- `TRY`を外すだけでは安全性を再現できない。Trino TRYも文書化された一部エラーだけを捕捉する。
- `TRY_CAST(url_decode(u) AS VARCHAR)`を万能な例外捕捉として使わない。
- 存在を確認していない`TD_PARSE_URL`のような関数名を作らない。
- URL全体をdecodeしてからhost等を解析すると、reserved delimiterの意味が変わり得る。
- Hive4ではDB修飾したTD UDFを使わず、`TD_URL_DECODE(...)`等の文書化された名前で呼ぶ。

## 4. ハッシュと文字列連結

### 同じ入力に対するアルゴリズムの基本形

```sql
-- Trino
SELECT LOWER(TO_HEX(SHA256(TO_UTF8('abc'))));
-- Hive
SELECT LOWER(SHA2('abc', 256));
```

標準SHA-256のASCII fixtureは[smoke期待値](../examples/smoke/expected.json)へ収録。
この一致だけでUnicode・NULL・serializationを含む既存IDの互換性は証明できない。

### 次は同等のID生成式ではない

```sql
-- TrinoのJSON配列をhashする有効な型付きの例
TO_HEX(SHA256(TO_UTF8(JSON_FORMAT(CAST(ARRAY['a', 'b'] AS JSON)))))

-- Hiveのtab区切り文字列をhashする別設計
SHA2(CONCAT_WS('\t', 'a', 'b'), 256)
```

`JSON_FORMAT`はJSON型を受ける。ARRAYを直接渡す擬似式と、`CAST(... AS JSON)`した式を混同しない。
前者は`["a","b"]`、後者はtab区切りの文字列を入力とするため、通常は違うhashになる。

互換性を左右するもの:

- 入力列・順番・型、JSONのbracket / quote / escaping、数値の小数桁・指数表記。
- SQL NULL、JSON null、空文字、欠損、`'null'`の違い。
- `concat_ws`のNULL処理。TrinoはNULL要素を飛ばす。Hive側は対象版でfixture確認する。
- 区切り衝突。例として`['a|b','c']`と`['a','b|c']`をnaiveに`|`で結ぶと同じ文字列になる。
- Unicode・encoding・正規化、改行、tab、timezone、object key順、hexの大文字 / 小文字。
- Presto350 → Trino423で変わるROW-to-JSON形状など、版によるserialization差。

**既存IDを維持する場合**は、同一の入力byte列とhex表記を再現し、preimageとhashの両方を比較する。
Hive serializerの見た目が同じでもbyte一致は実測する。確認できない場合は互換と呼ばない。
生成規則を変えるなら`id_v2`等に分け、履歴・JOIN・重複除外への影響を承認する。

### `||` → CONCAT

```sql
-- Trino
'n:' || CAST(customer_id AS VARCHAR)
-- Hive
CONCAT('n:', CAST(customer_id AS STRING))
```

NULL、空文字、数値の文字列表現を比較する。`CONCAT_WS`への変更はNULLや区切りの契約が別なので注意する。

## 5. JSON / 配列 / MAP

| Trino | Hiveでの候補 | 直置換しない理由 |
| --- | --- | --- |
| `json_extract_scalar(j,'$.id')` | `get_json_object(j,'$.id')` | 返すtext、path仕様、NULL、JSON型と文字列の差 |
| `json_parse(s)` | 型付きparser等を検討 | `CAST(s AS JSON)`とは別。Hive4 `JSON_READ`は型指定と異常値を要確認 |
| `ARRAY[1,2]` | `array(1,2)` | 要素型、NULL、空配列 |
| `a[1]`（最初） | `a[0]`（最初） | indexの基準が違う。JSON pathの`$[0]`とは分ける |
| `array_agg(x)` | `collect_list(x)`を候補 | Trino array_aggはNULLを保持。Hive側のNULL・順序・空入力を実測 |
| `array_agg(x ORDER BY t)` | 順序情報を保持した再集約設計 | 値sortとevent時刻順は別。tie-breakerも必要 |
| `CROSS JOIN UNNEST(a)` | `LATERAL VIEW explode(a)`を候補 | NULL / 空配列、位置、多配列、左行保持をfixture確認 |
| `LEFT JOIN UNNEST` | `LATERAL VIEW OUTER`を候補 | NULL / 空とNULL要素の区別、行数を確認 |
| `map[key]` | MAP lookupを版別確認 | missing key / duplicate key / NULL key契約 |

- Trino `json_parse('[1,2]')`はJSON配列。`CAST('[1,2]' AS JSON)`はJSON文字列。
- `json_format(json)`と`CAST(json AS VARCHAR)`も同義ではない。後者は配列 / objectに使えない。
- `json_extract`のJSONと`json_extract_scalar`のtextを混同しない。
- `json_array_get`は文字列要素で不正JSONを生成し得るため、upstream自身が非推奨と警告している。
- Trinoで欠損MAPキーを安全に読む場合は`element_at(map,key)`を検討する。
- 位置情報は値と別に保持する。NULL除去でindexがずれることを防ぐ。
- 多配列UNNESTのpadding、ordinalityとposexplodeの位置差などは、対象版で独立に確認する。

## 6. 日時・集約・近似

| 元の意味 | Hiveでの方針 | 注意 |
| --- | --- | --- |
| `TD_TIME_STRING(time,'d!','Asia/Tokyo')` | `TD_TIME_FORMAT(time,'yyyy-MM-dd','Asia/Tokyo')` | 日付文字列としての候補。全precisionへの一般化不可 |
| Trino timestamp / date関数 | TD Unix秒関数か対応native関数を選ぶ | 返り型、timezone、ミリ秒、DST、calendar境界 |
| `approx_distinct(x)` | 近似要件と利用可能関数を再確認 | `COUNT(DISTINCT)`はexactであり同じ性能・精度ではない |
| `approx_percentile(x,p)` | Hive percentile / percentile_approxの型と精度を確認 | exact側は受入型が限定。近似の精度パラメータ・結果は別 |
| `UNION` | 原則その意味を維持 | `UNION ALL`は重複を残すため意味変更 |

`TD_TIME_STRING`の`!`は単にtimezoneを消す記号ではない。
precisionで文字列を短くする。`d`は日初に切った完全な時刻文字列、`d!`は日付だけ。
詳しくは[SQL / UDF](sql-and-udfs.md)。

Hive4ではNULL sortの既定、予約語、numeric値をdate UDFへ渡す挙動、
`mask_hash`の既定MD5 → SHA256等の変更にも注意する。版移行とengine移行を同時に無検証で行わない。

## 7. 最終チェックリスト

- [ ] 実engine / version、`.dig` engineとSQL方言が一致。
- [ ] CAST / CASE、BIGINT維持、DECIMAL(p,s)、typed NULL、失敗castを確認。
- [ ] 正規表現とURLの境界fixtureを確認。
- [ ] ハッシュのpreimage・encoding・hexと既存IDを確認。
- [ ] JSON / 配列 / MAPのNULL、順序、位置、粒度を確認。
- [ ] 期間の半開区間、Unix秒、timezone、session / backfillを確認。
- [ ] WITHと出力SQLの位置、append / overwrite / retryを確認。
- [ ] 件数・schema・NULL数・金額・ID・重複と性能を比較。

## 出典

共通[S2–S5, S13](sources.md)に加え、Trino **423版**の
[conversion](https://trino.io/docs/423/functions/conversion.html)、
[conditional](https://trino.io/docs/423/functions/conditional.html)、
[types](https://trino.io/docs/423/language/types.html)、
[regexp](https://trino.io/docs/423/functions/regexp.html)、
[JSON](https://trino.io/docs/423/functions/json.html)、
[aggregate](https://trino.io/docs/423/functions/aggregate.html)、
[binary](https://trino.io/docs/423/functions/binary.html)、
[string](https://trino.io/docs/423/functions/string.html)、
[array](https://trino.io/docs/423/functions/array.html)、
[TD Hive4 migration](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/hive/hive4)を参照。
Bare DECIMALの既定は[Trino423実装](https://github.com/trinodb/trino/blob/423/core/trino-spi/src/main/java/io/trino/spi/type/DecimalType.java)でも確認。
