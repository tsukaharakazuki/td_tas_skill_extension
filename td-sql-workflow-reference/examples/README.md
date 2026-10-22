# Examples

このフォルダのSQLとWorkflowは**文書に基づくテンプレート**です。
作成時にTD実engineへ送信・実行していません。
秘密・profile・APIキー・schedule・メール送信・activationは含みません。

## 1. Read-only smoke SQL

- [Trino](smoke/trino.sql)
- [Hive](smoke/hive.sql)
- [期待値](smoke/expected.json)

テーブルを参照せず、2行のfixtureから次を確認するSELECTです。

| 列 | 期待 |
| --- | --- |
| `s` | a.b と axb |
| `has_literal_dot` | a.bはtrue、axbはfalse |
| `wide_id` | 2147483648。INTでは保持できない値 |
| `nullable_amount` | DECIMAL(18,2)として型付けしたNULL |
| `abc_hash` | ASCII文字列abcの標準SHA-256（lowercase hex） |

順序は未指定です。`expected.json`は期待値であって実行結果ではありません。
SHAのASCII例は、JSON配列と連結文字列の互換性を証明するものではありません。

利用可能な読み取りquery toolで、SQLに記したengineを指定してください。
これらはコンソール実行用なので、`DIGDAG_INSERT_LINE`は不要です。WFの出力タスクで使う場合は、HiveのWITHにマーカーを追加してください。
CLIの実構文・アカウントはその環境で確認します。アカウント / profileを勝手に切り替えません。
小さなSELECTでもremote jobであることを意識し、実行結果とengine版を記録します。

## 2. WITHと出力SQLの挿入位置

[workflow/](workflow/)は独立したWorkflowプロジェクトの形です。
`tdx.json`はproject名だけを持ち、認証やアカウントを指定しません。

- [main.dig](workflow/main.dig)
- [config/common.yml](workflow/config/common.yml)
- [queries/trino.sql](workflow/queries/trino.sql)
- [queries/hive.sql](workflow/queries/hive.sql)

既定は`allow_example_writes: false`でSQLタスクをskipします。
**このflag自体は承認手続きの代わりではありません。**
設定変更・push・runはそれぞれ影響を確認してから行ってください。

flagをtrueにした場合、定数1行の出力を2テーブルに作成する例です。

| task | engine | 出力 | 置換の影響 |
| --- | --- | --- | --- |
| trino_result | presto（Trino系） | `<config.database>.qa_sql_reference_trino` | 存在すればDROPしてCTAS |
| hive_result | hive | `<config.database>.qa_sql_reference_hive` | 表を確保してINSERT OVERWRITE |

スキーマ・time・保持方針を対象環境で確認してください。
両例は一つのWITH文です。Hiveは出力タスクでマーカーが必須で、CTEの後に置きます。Trinoのマーカーは任意で、置く場合はWITHの前に置きます。
`insert_into`の形も説明用に使えますが、変更するとappendとなり、再実行で重複し得ます。

### 安全な確認順

1. SQL、`.dig`、configを読む。placeholder DBを隔離QA DBへ置換する。
2. `allow_example_writes`は承認前にtrueへ変えない。
3. ローカルcheckerで各SQLを出力mode込みで点検する。
4. 使用するvalidatorの対象がmanifest / YAML / `.dig`のどれかを確認する。
5. deployの必要があれば、pushの差分previewとscheduleへの影響を確認し、承認してからpushする。
6. `tdx wf run <project.workflow> --dry-run`で予定タスクを確認する。
7. 対象2表の書込方式・既存データ消失の可能性・外部送信なし・fixture1行を説明し、明示承認を待つ。
8. 承認後にflagをtrueへ変更した場合は、その変更を反映し、再びdry-runして内容を確認してから実行する。
9. 結果、schema、件数、2回目の動作を記録する。片付けのDROPも確認してから行う。

これらのremote操作は、リポジトリの作成・ローカルテストには含まれません。

## 3. ローカルcheckerだけを試す

Skillルートをカレントにした例:

```bash
python3 -I scripts/check_sql.py --engine trino examples/smoke/trino.sql
python3 -I scripts/check_sql.py --engine hive examples/smoke/hive.sql
python3 -I scripts/check_sql.py --engine trino --output-mode create-table examples/workflow/queries/trino.sql
python3 -I scripts/check_sql.py --engine hive --output-mode create-table examples/workflow/queries/hive.sql
```

指摘がなくてもengine実行成功の証明ではありません。
