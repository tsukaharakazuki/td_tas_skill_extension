# td-claude2td-connect

Claude から Treasure Data に**読み取り専用**で接続するデスクトップ拡張機能 (`.mcpb`)。

API キーは利用者の PC の **OS キーチェーン**に保存され、Treasure Data への通信も利用者の PC から直接行われます。キーがクラウド側に渡ることはありません。

---

## インストール

### 方法 A: Claude に手伝ってもらう（推奨）

Claude デスクトップアプリで、このリポジトリをマーケットプレイスとして追加します。

```
/plugin marketplace add tsukaharakazuki/td_tas_skill_extension
```

`td-claude2td-connect` をインストールしたあと、

> ClaudeからTreasure Dataに接続したい

と話しかけると、セットアップウィザードが起動します。TD 側の権限設計から疎通確認まで順に案内します。

### 方法 B: 手動

1. [`dist/td-claude2td-connect-0.1.0.mcpb`](dist/td-claude2td-connect-0.1.0.mcpb) をダウンロード
2. ダブルクリック（または 設定 → 拡張機能 → 詳細設定 → 拡張機能をインストール…）
3. API キーとリージョンを入力して有効化

**動作要件**: Claude デスクトップアプリ（macOS / Windows）。ブラウザ版・モバイル版では利用できません。

---

## 設定項目

| 項目 | 必須 | 既定値 | 説明 |
|---|---|---|---|
| Treasure Data API キー | ✅ | — | 読み取り専用ユーザーの **Master Key**。Write-only Key ではクエリを実行できません |
| リージョン | ✅ | `jp01` | `us01` / `jp01` / `eu01` / `ap02` / `ap03` |
| 既定のデータベース | | — | よく使うデータベース名。会話中に切り替えも可能 |

リージョンはコンソールの URL から判別できます（`console.treasuredata.co.jp` → `jp01`）。

---

## ⚠️ 先に Treasure Data 側を設定してください

クエリ実行には Master Key が必要で、Master Key は**そのユーザーの権限をすべて持ちます**。普段使いのアカウントのキーをそのまま貼らないでください。

1. Control Panel → **Users** で専用ユーザーを作成
2. Control Panel → **Policies** で参照のみのポリシーを作り、**Claude に見せてよいデータベースだけ**を対象に含める
3. そのポリシーを専用ユーザーに割り当てる
4. そのユーザーの **My Settings → API Keys** から Master Key を取得

**この拡張機能の読み取り専用ロックは多層防御の一層であって、権限管理の代わりにはなりません。** 実効的な境界は上記のポリシーです。

---

## 提供されるツール（19、すべて参照系）

**データ**
`list_databases` / `list_tables` / `describe_table` / `query` / `use_database` / `current_database`

**CDP**
`list_parent_segments` / `get_parent_segment` / `list_segments` / `get_segment` / `list_activations` / `parent_segment_sql` / `segment_sql`

**Workflow**
`list_projects` / `list_workflows` / `list_sessions` / `get_session_attempts` / `get_attempt_tasks` / `get_task_logs`

### 意図的に塞いでいるもの

| ツール | 理由 |
|---|---|
| `execute` | 書き込み SQL の実行 |
| `kill_attempt` | ワークフローの停止 |
| `retry_session` / `retry_attempt` | ワークフローの再実行 |

これらはツール一覧に現れず、直接呼び出しても拒否されます。設定で有効化する手段はありません。

---

## セキュリティ設計

| | この拡張機能 |
|---|---|
| API キーの保存先 | OS キーチェーン（マスク入力、平文ファイルなし） |
| キーの到達範囲 | 利用者の PC 内のみ |
| TD への通信経路 | 利用者の PC から直接 |
| 書き込み | 設定で有効化できないようロック |
| 監査証跡 | TD 側のジョブ履歴 |

### 公式サーバーへの加工点

本拡張機能は Treasure Data 公式の MCP サーバー [`@treasuredata/mcp-server`](https://github.com/treasure-data/td-mcp-server) (Apache-2.0) を **無改変で同梱**し、起動前にランチャー (`src/server/index.js`) で以下を行います。

1. **`TD_ENABLE_UPDATES` を `false` に固定** — 外部から有効化できません
2. **SQL 検証の強化** — 公式の読み取り専用判定は行コメント (`--`) しか除去しないため、ブロックコメントで書き込みを偽装できます:

   ```
   "DROP TABLE t"            → BLOCK  （正しく拒否される）
   "/* x */ DROP TABLE t"    → ALLOW  （UNKNOWN と判定されて通ってしまう）
   ```

   ランチャーはブロックコメント・行コメント・文字列リテラルを除去したうえで再判定し、`SELECT` / `WITH` / `SHOW` / `DESCRIBE` / `EXPLAIN` で始まらない文、および書き込みキーワードを含む文を拒否します。文字列リテラルを除去しているため `WHERE event = 'delete'` のような正当なクエリは通ります。
3. **状態を変えるツールの除去** — 上表の 4 ツールを一覧からも呼び出し経路からも外します
4. **フェイルクローズ** — 上記のガードを適用できなかった場合は、サーバーを起動せずに終了します

### 既知の制限

- 公式サーバーの監査ログはプロセス内のメモリにのみ保持され、永続化されません。**監査証跡は TD 側のジョブ履歴**を参照してください
- `query` は既定 40 行（最大 10000 行）を返します。これは返却行数の上限であって**スキャン量の上限ではありません**

---

## ソースからビルドする

```bash
cd src/server && npm install --omit=dev
cd .. && npx @anthropic-ai/mcpb pack . ../dist/td-claude2td-connect-0.1.0.mcpb
```

同梱する公式サーバーのバージョンは `src/server/package.json` で **完全固定**しています（`npx` で実行時に最新版を取得する構成にはしていません）。

---

## ライセンス

Apache-2.0。同梱している `@treasuredata/mcp-server` も Apache-2.0 です。詳細は `src/NOTICE` を参照してください。

## 不具合報告

https://github.com/tsukaharakazuki/td_tas_skill_extension/issues
