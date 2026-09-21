# td-claude2tdx-connect

Treasure AI の公式 CLI **[tdx](https://tdx.treasuredata.com/)** を Claude から使うデスクトップ拡張機能 (`.mcpb`)。

クエリ、CDP セグメント、ジャーニー、Engage、ワークフロー、ジョブまで tdx が扱えるものはひととおり操作できます。API キーは利用者の PC の **OS キーチェーン**に保存され、Treasure Data への通信も利用者の PC から直接行われます。

> **参照しかしないなら [`td-claude2td-connect`](../td-claude2td-connect/) の方が安全です。** そちらは 19 個の参照系ツールだけを公開し、書き込みが構造的に不可能です。この拡張機能は性格が異なります（下記「権限について」）。

---

## インストール

### 方法 A: Claude に手伝ってもらう（推奨）

```
/plugin marketplace add tsukaharakazuki/td_tas_skill_extension
```

`td-claude2tdx-connect` をインストールしたあと、

> tdxをClaudeから使いたい

と話しかけると、権限モードの選定から疎通確認まで案内します。

### 方法 B: 手動

1. [`dist/td-claude2tdx-connect-0.1.0.mcpb`](dist/td-claude2tdx-connect-0.1.0.mcpb) をダウンロード
2. ダブルクリック（または 設定 → 拡張機能 → 詳細設定 → 拡張機能をインストール…）
3. 設定を入力して有効化

**動作要件**: Claude デスクトップアプリ（macOS / Windows）、**Node.js 22.12 以上**。

---

## 設定項目

| 項目 | 必須 | 既定値 | 説明 |
|---|---|---|---|
| Treasure Data API キー | △ | — | 専用ユーザーの Master Key。プロファイルを使う場合は空欄 |
| tdx プロファイル名 | △ | — | この PC で `tdx profile create` 済みの場合のみ。**指定するとこちらが優先** |
| リージョン | ✅ | `jp01` | `us01` / `jp01` / `eu01` / `ap02` / `ap03` |
| 権限モード | ✅ | `full` | `full` / `operate` / `readonly` |
| 管理コマンドを許可する | | オフ | `user` / `policy` の**変更**を許可 |

API キーとプロファイル名は、どちらか一方が必要です。

---

## ⚠️ 権限について

**この拡張機能の権限モードは、セキュリティ境界ではありません。**

`tdx mcp` が公開するツールは実質 1 つ (`tdx_run`) で、任意の tdx CLI コマンドを実行します。読み取り専用モードは tdx 側に存在しません。そのため「このツールだけ許可する」という制御が原理的に効かず、**実効的な境界は API キーが指す Treasure Data ユーザーの権限だけ**です。

権限モードは、その手前で事故を減らすための安全装置です。設定画面で利用者自身が変更できるので、これだけを頼りにしないでください。

### 先に Treasure Data 側を設定してください

1. Control Panel → **Users** で用途専用のユーザーを作成
2. Control Panel → **Policies** でポリシーを作成し、**対象データベースと操作範囲を実際の用途まで絞る**
3. そのポリシーをユーザーに割り当てる
4. そのユーザーの **My Settings → API Keys** から Master Key を取得

管理者アカウントのキーをそのまま使わないでください。

---

## 権限モード

| モード | 内容 |
|---|---|
| `readonly` | 参照コマンドのみ。`query` は SELECT / WITH / SHOW / DESCRIBE / EXPLAIN のみ |
| `operate` | 上記＋ `workflow` / `job` / `schedule` の実行・再実行・停止。定義変更は不可、SQL は参照のみ |
| `full` | 全コマンド（既定） |

`readonly` では `work_create_item` ツールも非表示になります。

### モードに関係なく常に禁止

| コマンド | 理由 |
|---|---|
| `auth` / `profile` / `profiles` | 認証情報の操作（tdx 自身もブロック） |
| `mcp` | MCP サーバーの入れ子起動 |
| `upgrade` | 同梱している tdx を書き換えてしまう |
| `claude` / `codex` | 対話型エージェントの起動。ツール呼び出しが返らなくなる |

### 管理コマンドの別扱い

`user` と `policy` の**変更**は、モードとは独立した「管理コマンドを許可する」スイッチで制御します（既定オフ）。`policy` は権限そのものを書き換えられるためです。参照（`users`、`policy list`）はオフのままでも行えます。

---

## 提供されるツール

| ツール | 内容 |
|---|---|
| `tdx_run` | tdx CLI コマンドの実行（権限モードで許可された範囲） |
| `tdx_search` | 自然文から該当コマンドを検索 |
| `work_create_item` | ワークスペースに作業アイテムを作成（`readonly` では非表示） |

ツール一覧の `tdx_run` の説明には、現在の権限モードが追記されます。

---

## 実装

tdx を**無改変で同梱**し、`tdx mcp` を子プロセスとして起動したうえで、**MCP の JSON-RPC を中継するプロキシ**（`src/server/index.js`）として権限モードを適用しています。

内部を書き換えるのではなくプロトコル層で処理しているのは、tdx が月次のカレンダーバージョン（`2026.9.0` など）で更新され、配布物も難読化されているためです。プロトコルに依存する限り、tdx の実装変更で壊れません。

- `tdx_run` の呼び出しは、tdx に渡る前に `src/server/policy.js` で検査されます
- `readonly` / `operate` での SQL 検証は、ブロックコメント・行コメント・文字列リテラルを除去してから判定します（`WHERE event = 'delete'` のような正当なクエリは通ります）
- 認証情報の解決は tdx に委ねています。プロファイル名が指定された場合は `TDX_PROFILE` を渡し、API キーは渡しません

### 既知の制限

- **同梱している tdx のバージョンは固定**です（`src/server/package.json`）。tdx は更新が速いため、新機能を使いたい場合はこの拡張機能の更新を待つか、ターミナルで `tdx` を直接使ってください。拡張機能内の `tdx upgrade` は禁止しています
- `tdx_run` の実行は **15 分でタイムアウト**します（tdx 側の仕様）。長いクエリは `job submit` を使ってください
- `-y` / `--yes` を付ければ確認プロンプトは飛びます。プロキシはこれを妨げません

---

## ソースからビルドする

```bash
cd src/server && npm install --omit=dev
cd .. && npx @anthropic-ai/mcpb pack . ../dist/td-claude2tdx-connect-0.1.0.mcpb
```

---

## ライセンス

Apache-2.0。同梱している `@treasuredata/tdx` の帰属は `src/NOTICE` を参照してください。

## 不具合報告

https://github.com/tsukaharakazuki/td_tas_skill_extension/issues
