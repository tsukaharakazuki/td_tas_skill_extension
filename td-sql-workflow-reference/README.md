# td-sql-workflow-reference

Treasure AI Studio / Treasure Workで、Treasure Dataの**SQL作成・エラー診断・Trino → Hive移行・Workflowデバッグ**を一つの入口から行うためのSkillです。

公式SQL Skillを参考にしつつ、関数の置換だけで終わらない実務上の判断と、SQLを実行する`.dig`の設定をまとめます。
公式ドキュメント全文の複製や、全関数を網羅したAPI辞書ではありません。重要な差分を整理し、未知の関数は稼働版の公式資料へ戻る構成です。

## 使い方

このフォルダをSkillとして読み込むか、[SKILL.md](SKILL.md)を入口として参照してください。
他のSQL / Workflow Skillがインストールされていなくても、基本手順と参照資料を辿れます。
リポジトリのmarketplaceにも同名pluginとして登録しています。
ZIP配布時は`td-sql-workflow-reference/`を唯一の最上位フォルダとし、その直下の`SKILL.md`と補助ファイルをまとめます。

依頼例:

- 「TDで直近7日分の会員別購買集計SQLとWorkflowを作って」
- 「このTrinoのメモリエラーを診断し、必要ならHiveに移行して」
- 「Consoleでは通るWITH付きSQLがWorkflowのcreate_tableで失敗する」
- 「Hiveへ変更したら正規表現の抽出件数と顧客IDが変わったので調べて」

原因特定を速くするには、元SQL、`.dig`、include設定、エラー全文、実engine、job ID、入出力スキーマを添えてください。
秘密・APIキー・実顧客の個人情報は含めないでください。

## 読み分け

| 資料 | 内容 |
| --- | --- |
| [SKILL.md](SKILL.md) | AI向けの入口、作成 / 診断 / 移行の手順、安全境界、回答形式 |
| [SQL / TD UDF](references/sql-and-udfs.md) | TD関数、timeパーティション、日時、型・NULL、新規SQL |
| [エンジンとメモリ](references/engines-and-memory.md) | 契約条件と実メモリ、JOIN膨張、Trino維持 / Hive移行判断 |
| [Trino → Hive](references/trino-to-hive.md) | 型、正規表現、TRY、URL、JSON、ハッシュ、配列、日時 |
| [Workflow](references/workflow.md) | td>、WITHと挿入位置、出力方式、設定scope、リトライ |
| [診断プレイブック](references/debugging.md) | エラー症状別の切り分け、ConsoleとWFの違い |
| [意味互換・QA](references/validation.md) | NULL、精度、件数、ID、期間境界、再実行の検証 |
| [出典と更新方針](references/sources.md) | 公式URL、確認日、バージョン、確認できた範囲 |
| [examples](examples/README.md) | 両engineのread-only smoke SQLとWorkflow出力例 |

## 特に防ぎたい誤り

1. **CASEとCASTの混同**: `CAST(x AS VARCHAR)`等の型変換と`CASE WHEN`は別です。
2. **BIGINTの縮小**: Hiveでも通常はBIGINTを維持します。INTへの一括置換は桁あふれリスクがあります。
3. **正規表現の層**: SQLファイル内でTrinoの`'\.'`とHiveの`'\\.'`は異なる文字列表現です。YAML等を重ねた場合はさらに確認します。
4. **TRYを外した意味変更**: 不正入力時の例外 / NULLの扱いが変わります。
5. **ハッシュの非互換**: JSON配列とtab区切り連結は原則別の入力バイト列で、同じIDにはなりません。
6. **WITHと出力SQLの位置**: `-- DIGDAG_INSERT_LINE`は、WFで出力するHiveのWITH文では必須（CTEの後）です。コンソール実行やTrinoでは不要です。
7. **メモリとテーブルサイズの混同**: JOIN / 集約の中間状態と、保存データ量は別です。

### CPUとメモリの記載について

「契約CPU 1ユニットあたり10GB（例: 10CPU = 100GB）」は、作成依頼で提供された**契約・運用前提**として収録しています。
公開公式資料で比率を確認できた普遍仕様とはしていません。実環境の契約・利用状況・ジョブログを確認します。

## オフラインの補助チェック

Python 3.10以上、標準ライブラリのみ。ネットワーク接続、SQL実行、ファイル書換えは行いません。
コマンドはこのフォルダをカレントディレクトリにした例です。

```bash
# SQLファイル中の既知の移行リスクを指摘
python3 -I scripts/check_sql.py --engine hive path/to/query.sql

# td>のcreate_table利用を前提に、WITH / マーカーも点検
python3 -I scripts/check_sql.py --engine hive --output-mode create-table path/to/query.sql

# JSON出力
python3 -I scripts/check_sql.py --engine trino --json examples/smoke/trino.sql

# checker自体のローカルユニットテスト
python3 -I tests/test_check_sql.py
```

これは**ヒューリスティックなrisk checker**です。SQL parser、YAML / Digdag validator、engine実行テストではありません。
指摘がゼロでも正しさを保証しません。既知パターンの誤検知・見逃し、未展開テンプレート、動的SQLに注意してください。
終了コードは`0`（既知の指摘なし）、`1`（要確認の指摘あり）、`2`（引数 / ファイルの問題）です。
詳細は[tests/README.md](tests/README.md)を参照してください。
Skillの手動受け入れ確認用に[9つの依頼シナリオ](tests/scenarios.json)も収録しています。これは自動評価の実行結果ではありません。

## 検証状況・安全性

2026-10-22のローカル確認結果:

- checkerユニットテスト **73件成功**。
- 同梱SQL **4本**は、それぞれのengine / 出力mode指定で既知の指摘なし。
- Workflow例とconfigはYAML構文解析成功（include展開・Digdag実行は対象外）。
- Markdownのローカル参照リンク、JSON、marketplaceの登録パスを確認。
- 9つのSkill依頼シナリオは手動評価用に収録。LLM自動評価は未実施。

- 配布するsmoke SQLは期待値を添えていますが、**この作成作業ではTDの実engineで実行していません**。
- ローカルテストはcheckerの振る舞いを確認するものです。TD製品仕様の認証試験ではありません。
- Workflow例はテンプレートです。出力先を置換し、影響・対象規模を確認してから実行します。
- `tdx wf run`は先にdry-runし、外部送信も含めて明示承認後に実行します。
- 本SkillはTD設定変更、Workflowデプロイ、メール送信やactivationを自動で行いません。

作成: Treasure Work。公式資料の確認日と未確認事項は[出典](references/sources.md)を参照してください。
