# Treasure Workflow / Digdag

SQLの方言だけでなく、**SQLに何が挿入され、どこで、どの設定で実行されるか**を確認する。
upstream DigdagとTD hostedの対応範囲、`td` toolbeltと`tdx`の構文を区別する。

## 1. td>の基本とengine名

```yaml
timezone: Asia/Tokyo

_export:
  td:
    database: qa_db
    engine: presto

+query:
  td>: queries/result.sql
  create_table: qa_result
```

- `td>`の文書化されたengine値は**`presto` / `hive`** [S9]。
  TDのTrino製品名から`engine: trino`へ機械的に書き換えない。
- `engine`はタスクで指定するか、`td.engine`としてexportする。実ジョブでも確認する。
- SQLは外部`.sql`が扱いやすい。inlineの公式expanded形式は次の**兄弟queryキー**。

```yaml
+query:
  td>:
  query: |
    SELECT 1 AS value
```

`td>:`の下へ`query:`をネストする例と混同しない。

## 2. create_table / insert_intoはSQLを生成する

| engine | `create_table: result` | `insert_into: result` |
| --- | --- | --- |
| `presto`（TD Trino系） | `DROP TABLE IF EXISTS result; CREATE TABLE result AS` | `INSERT INTO result` |
| `hive` | `INSERT OVERWRITE TABLE result` | `INSERT INTO TABLE result` |

表は構造を示す。実際には識別子の引用符・DB修飾等が付く。
Hiveのcreate_tableと両engineのinsert_intoでは、operatorがAPIで表の存在も確保する。
文書とupstream実装に基づく整理であり、TD deployed forkの実行確認ではない [S9, W1]。

- **`create_table`と`insert_into`は同時指定しない**。
- 文書化された`td>`の`overwrite: true`フラグはない。出力方式を明示して選ぶ。
- Trinoのcreate_tableはDROP + CTAS。**atomic swapではなく、失敗時に出力を失う可能性がある**。
- Hiveのcreate_tableは同じDROP / 再作成ではない。既存表のschemaやstreaming更新も確認する。
- HiveのINSERT OVERWRITEはstreaming中の表には非推奨。直近 / 同時流入行が残る注意点がある [W2]。
- insert_intoはappend。独立した再実行で重複し得る。
- SQLに自分でDDL / INSERTを書く場合は、自動出力指定と重ねない。
- 出力表の`time`、スキーマ、保持・期間、権限は別途確認する。

## 3. WITHと -- DIGDAG_INSERT_LINE

このコメントは`td>`の出力SQL挿入位置を指定する。SQLを解析して自動でCTEの末尾へ移す機能ではない。
出力指定がないSQLではただのコメント。

### Hive: CTEの後、最後のSELECTの直前

```sql
WITH src AS (
  SELECT user_id FROM source_db.events
)
-- DIGDAG_INSERT_LINE
SELECT user_id FROM src
```

create_tableで生成するSQLの形:

```sql
WITH src AS (
  SELECT user_id FROM source_db.events
)
INSERT OVERWRITE TABLE result
SELECT user_id FROM src
```

insert_intoなら中間行が`INSERT INTO TABLE result`になる。
**WITHから最後のSELECTまで一つの文**なので、CTEとマーカーの間に`;`を置かない。
TD自身が`WITH ... INSERT ... SELECT`を文書化している [W2]。
マーカーなしで前置すると`INSERT ... WITH ...`となり、この構造と異なる。

### Trino / presto: WITHの前

```sql
-- DIGDAG_INSERT_LINE
WITH src AS (
  SELECT user_id FROM source_db.events
)
SELECT user_id FROM src
```

create_tableで生成するSQLの形:

```sql
DROP TABLE IF EXISTS result;
CREATE TABLE result AS
WITH src AS (
  SELECT user_id FROM source_db.events
)
SELECT user_id FROM src
```

insert_intoなら`INSERT INTO result WITH ... SELECT ...`。
TrinoのINSERT / CTASは、その後ろにWITH付きqueryを置く構文 [W3]。
Trinoでは既定の前置位置で動作する場合もあり、全WITHでマーカー必須とは言わない。
**Hive用のCTE後マーカーを、そのままTrinoへ持ち込まない**。

### マーカーの書式

- 安全な規約として、**列1から、単独行に、正確に`-- DIGDAG_INSERT_LINE`を一度だけ**書く。
- inspected upstream実装は改行または先頭直後の`--`を探し、最初のmatchだけを置換する [W1]。
  行頭に空白を入れたものや、コード末尾のコメントを同じものとみなさない。
- 実装はSQL parserではない。文字列やblock comment中の同名テキストも避ける。
- checkerは文字列・block comment内を「有効なマーカー」とは扱わないが、
  実operatorの文字列置換がそれらを必ず安全に無視するという保証ではない。
- SQLファイル先頭コメント、複数statement、自前DDLのある場合は展開後SQLまで読む。

## 4. 設定・include・展開

Digdagのincludeは次の構文。`!include :`の空白も保持する [W4]。

```yaml
_export:
  config:
    !include : config/common.yml

+show_period:
  echo>: "period=${config.start_date}..${config.end_date}"
```

- `_export`は当該タスクと子タスクへ作用する。nested scopeをグローバル状態とみなさない。
- task local、export、store、built-inのscopeを区別する。storeは後続タスクへ見える。
- built-inを上書きできると想定しない。並列枝の`td.last_results`を共有集約として使わない。
- **本Skillの運用推奨**: 開発条件はconfigファイルへ明示し、実効値を秘密を除いてログへ出す。
- CLIパラメータで`_export`を確実に上書きできるとは想定しない。
  upstream `--param`についても`_export`は上書きできないと文書化されている [W4]。
- 展開済みのleaf設定や単純な参照を使い、nested `_export`の連鎖展開へ依存しない。
  これは信頼性のための推奨であり、全nested変数を製品が禁止するという主張ではない。

### YAMLの三項演算子

```yaml
# 悪い例: plain scalarに ': ' を含む
engine: ${use_hive ? 'hive' : 'presto'}

# 値全体をquoteする例
engine: "${use_hive ? 'hive' : 'presto'}"
```

YAMLのplain scalar内の`: `はmappingと衝突する [W5]。
分岐が不要ならconfigでengineを固定する。ローカルdry-runで通っただけでserver側も通るとは断定しない。

### 正規表現の層

`.sql`または`query: |`はYAMLのdouble-quoteによるescape処理を避けられる。
それでもSQL文字列とregex自身の規則は残る。
YAML double-quote → `${...}`内JavaScript → SQL文字列 → regexのどの層があるかを数え、
展開後の文字列とfixtureで確認する。単純な「常に4本」などの規則を作らない。

## 5. 時間・並列・結果変数

- `session_time`は論理session時刻であり、実起動時刻 / 現在時刻とは限らない。
- 日次scheduleのsessionは通常その日の境界時刻で、実行時刻とは別 [W6]。
- retry / backfillはsession基準で同じ対象期間になるようにする。
- workflow timezoneとSQLのtimezoneを明示する。`${moment()}`やSQLのnowで対象が動く設計に注意する。
- `for_each>`の複数リストは組合せでありzipではない。
- `for_each>`の`_parallel: {limit: N}`は反復の並列数を制御する。pool上限とは別 [W7]。
- `td_for_each>`は`${td.each.COLUMN}`を使う。別operatorの全オプションを流用しない。
- `store_last_results: true`の`td.last_results`は**最初の1行**。全結果の保持ではない [S9]。

## 6. retry / errorはrollbackではない

- `_retry`をgroupへ付けると、先に成功した子も含めてgroupの先頭から再実行され得る [W4]。
- `job_retry`はTDジョブ要求のretry制御。Digdagのgroup retryとは別。
  毎回のjob IDが同じ、必ず新しいジョブになる等は未確認のまま断定しない。
- `_error`は失敗時の処理であり、出力・メール・HTTPを元へ戻すものではない。
- append、DROP + CTAS、streaming中のoverwrite、外部activationは、それぞれ再実行方針を決める。
- 再試行・再開の前に完了済みタスク、途中出力、送信済み対象、skip / resume対象を確認する。

## 7. TD hostedの境界と検証

TD hostedではupstreamの全operatorが使えるわけではない [W8]。
`sh>` / `rb>` / `embulk>`等の制約や、`download_file`非対応を確認する。
Custom Scriptの`py>`はローカルshell実行とは別。task fan-out・TTL・同時実行・archive容量の上限も現行資料で確認する。

- `manifest.yml`のvalidatorはmanifestの検証であり、SQL構文検証とは限らない。
- `digdag check`、`digdag run --dry-run`、`tdx wf push --dry-run`の目的を混同しない。
- 現行`tdx`の実構文は`--help`で確認する。存在しない`tdx wf start` / `validate`を作らない。
- `tdx`のglobal `-p`をworkflow引数の略と想定しない。profileを変更しない。
- `tdx wf push --dry-run`は差分preview。実pushはremote変更であり、scheduleにも影響し得る。
- `tdx wf run ... --dry-run`の後、SQL書込・外部送信・対象規模を説明して明示承認を待つ。
- `preview`を副作用ゼロのvalidateと決めつけない。
- engine実行・意味互換・大規模性能は[別のQA段階](validation.md)で確認する。

## 追加出典

- [W1] [td> implementation（upstream、TD deployed forkは未確認）](https://github.com/treasure-data/digdag/blob/master/digdag-standards/src/main/java/io/digdag/standards/operator/td/TdOperatorFactory.java)
- [W2] [TD Writing Hive Queries](https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/hive/writing_hive_queries)
- [W3] [Trino INSERT](https://trino.io/docs/423/sql/insert.html)、[CTAS](https://trino.io/docs/423/sql/create-table-as.html)、[SELECT](https://trino.io/docs/423/sql/select.html)
- [W4] [Workflow definition](https://docs.digdag.io/workflow_definition.html)、[command reference](https://docs.digdag.io/command_reference.html)
- [W5] [YAML 1.2.2](https://yaml.org/spec/1.2.2/)
- [W6] [Digdag scheduling](https://docs.digdag.io/scheduling_workflow.html)
- [W7] [for_each>](https://docs.digdag.io/operators/for_each.html)、[td_for_each>](https://docs.digdag.io/operators/td_for_each.html)
- [W8] [TD Workflow prerequisites and limitations](https://docs.treasure.ai/requirements-and-limitations/treasure-workflow-prerequisites-and-limitations)
- [W9] [Current tdx workflow commands](https://docs.treasure.ai/treasure-code/commands/workflow)

S系の共通出典は[sources.md](sources.md)を参照する。
