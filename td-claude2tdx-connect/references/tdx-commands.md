# tdx コマンド early reference

すべて `tdx --site "$TDX_SITE" <以下>` の形で実行する。出力を構造化したいときは `--json` / `--jsonl` / `--tsv` を付ける。表として読むなら `--table`。

## データ

| やりたいこと | コマンド |
|---|---|
| データベース一覧 | `databases` |
| テーブル一覧 | `tables -d <db>` |
| スキーマ確認 | `describe <db>.<table>` |
| 中身をざっと見る | `show <db>.<table>` |
| クエリ実行 | `query "<SQL>"` |
| 長いクエリ | `job submit "<SQL>"` → `job status <id>` → `job result <id>` |
| ジョブ一覧 | `jobs` |

`query` は Trino。`tdx_run` は15分でタイムアウトするため、重いクエリは `job submit` に回す。

## CDP

| やりたいこと | コマンド |
|---|---|
| 親セグメント一覧 | `parent-segment list` / `ps list` |
| セグメント一覧 | `segments` |
| セグメント詳細 | `segment get <name>` |
| アクティベーション一覧 | `activations <parent_name>/<child_name>` |
| ジャーニー一覧 | `journeys` |
| ジャーニー詳細 | `journey get <id>` |

## ワークフロー

| やりたいこと | コマンド |
|---|---|
| プロジェクト一覧 | `workflow project list` |
| ワークフロー一覧 | `workflow list` |
| 実行 | `workflow start <project> <workflow>` |
| セッション確認 | `workflow session list` |
| ログ | `workflow log <attempt_id>` |

## Engage / 配信

| やりたいこと | コマンド |
|---|---|
| ワークスペース一覧 | `engage workspace list` |
| キャンペーン一覧 | `engage campaign list` |
| テンプレート一覧 | `engage template list` |
| 送信元一覧 | `delivery sender list` |

## 探し方が分からないとき

```
tdx --site "$TDX_SITE" search "<やりたいこと>"
```

自然文から該当コマンドを引ける。手当たり次第に `--help` を叩くより速い。

## クエリを書くときの流儀

- **まず `describe` でスキーマを確認する。** カラム名を推測で書かない
- `time` カラムは Unix 秒。期間で絞るときは `TD_TIME_RANGE(time, '2026-01-01', '2026-02-01')` または `TD_INTERVAL(time, '-7d')` を使う。全期間スキャンは高コスト
- 探索段階では `LIMIT` を付ける。件数を知りたいだけなら `COUNT(*)` だけを投げる
- 結果が大きいときは全件を会話に展開しない。集計するか、件数と代表行を示してユーザーに方針を聞く
- データベース名に当たりを付けたいときは `databases` の結果を絞り込む。TD の環境はデータベース数が1000を超えることがあり、全件列挙は読みづらい

## 出力の扱い

`--json` で受けて、必要な列だけを整形して見せる。生の表をそのまま貼るより、ユーザーが聞いたことに答える形にまとめる。行数が多い場合はファイルに書き出して渡す方が読みやすい。
