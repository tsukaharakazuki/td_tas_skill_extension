---
name: td-claude2td-connect
description: 'Use when the user wants to connect Claude to Treasure Data so that they can run SQL and inspect schemas from a conversation, or when they need help installing, configuring, or troubleshooting the Treasure Data read-only extension (.mcpb). Triggers on phrases like "ClaudeからTDに接続したい", "TreasureDataに繋ぎたい", "TDのSQLをClaudeから実行したい", "TD接続の設定", "APIキーの設定", "td-claude2td-connect", "TD拡張機能が動かない", "connect Claude to Treasure Data", "set up the TD MCP".'
---

# Claude → Treasure Data 接続セットアップ

Claude から Treasure Data に**読み取り専用**で接続するための対話型セットアップ。`td-claude2td-connect` 拡張機能 (`.mcpb`) を各ユーザーの PC にインストールし、そのユーザー自身の API キーを OS キーチェーンに保存させる。

**設計方針**: API キーはユーザーの PC から外に出ない。Treasure Data への通信もユーザーの PC から直接行われ、クラウド側を経由しない。

---

## 前提

- **Claude デスクトップアプリ**（macOS または Windows）が必要。ブラウザ版・モバイル版には拡張機能をインストールできない
- Treasure Data のアカウントと、対象データベースへの参照権限
- Node.js の別途インストールは不要（デスクトップアプリに同梱のものを使う）

ユーザーがブラウザ版を使っている場合は、ここで「デスクトップアプリからやり直してください」と伝えて中断する。

---

## 実行フロー

ユーザーに **Step 1 → 5 の全体像を最初に伝えてから**、1 ステップずつ進める。各ステップの完了をユーザーに確認してから次へ進むこと。まとめて全部を指示しない。

---

### Step 1: Treasure Data 側で読み取り専用ユーザーを用意する

**ここが一番重要。飛ばさない。**

この拡張機能はクエリ実行に Master Key を使う（Write-only Key ではクエリできない）。Master Key は本来そのユーザーの権限すべてを持つため、**普段使いの個人アカウントのキーを貼らせない**。

ユーザーに以下を依頼する:

1. TD コンソールの **Control Panel → Users** で、この用途専用のユーザーを作る（例: `claude-readonly@example.com`）
2. **Control Panel → Policies** で参照のみのポリシーを作り、**Claude に見せてよいデータベースだけ**を対象に含める
3. そのポリシーを 1 で作ったユーザーに割り当てる
4. そのユーザーでログインし、**My Settings → API Keys** から **Master Key** をコピー

すでに読み取り専用の運用ユーザーがある場合はそれを使ってよい。

> 「とりあえず自分のキーで試したい」と言われた場合は、検証用データベースだけが見えるユーザーを作る方が結局早い、と一度だけ伝える。それでも本人が自分のキーで進めると決めたなら、後から差し替えられること（Step 4 で再設定できる）を伝えて先に進む。

**リージョン ID** も一緒に控えてもらう。コンソールの URL から判別できる:

| コンソールの URL | リージョン ID |
|---|---|
| `console.treasuredata.co.jp` | `jp01` |
| `console.treasuredata.com` / `console-next.us01...` | `us01` |
| `console.eu01.treasuredata.com` | `eu01` |
| `console.ap02.treasuredata.com` | `ap02` |
| `console.ap03.treasuredata.com` | `ap03` |

---

### Step 2: 拡張機能をダウンロードする

以下の URL をユーザーに渡し、ブラウザでダウンロードしてもらう:

```
https://github.com/tsukaharakazuki/td_tas_skill_extension/raw/main/td-claude2td-connect/dist/td-claude2td-connect-0.1.0.mcpb
```

- ファイル名: `td-claude2td-connect-0.1.0.mcpb`（約 3.3 MB）
- ブラウザによっては「この種類のファイルは危険」と警告が出る。ZIP 形式のアーカイブなので、保存して問題ない

---

### Step 3: インストールする

ダウンロードしたファイルを**ダブルクリック**する。うまく開かない場合は:

**Claude デスクトップアプリ → 設定 → 拡張機能 → 詳細設定 → 拡張機能をインストール…** からファイルを選ぶ。

インストール画面が開き、拡張機能の内容と権限が表示される。

---

### Step 4: API キーを設定する

インストール画面、または **設定 → 拡張機能 → Treasure Data (read-only)** で以下を入力してもらう:

| 項目 | 入力する値 |
|---|---|
| **Treasure Data API キー** | Step 1 で取得した Master Key |
| **リージョン** | Step 1 で確認したリージョン ID（既定値は `jp01`） |
| **既定のデータベース** | 任意。空欄可 |

API キーの入力欄はマスクされ、値は **OS のキーチェーン**に保存される。設定ファイルにも会話履歴にも平文では残らない。

**ユーザーに API キーを会話に貼らせないこと。** Claude 側でキーを受け取る必要はなく、受け取ってしまうと会話履歴に残る。もしユーザーが貼ってしまったら、その場で「この会話にキーが残ったので、TD 側でこのキーを失効させて作り直してください」と伝える。

入力後、拡張機能を**有効化**してもらう。

---

### Step 5: 疎通確認

新しい会話を開始してもらい（拡張機能は会話の開始時に読み込まれる）、こちらから `list_databases` を実行して確認する。

成功したら、Step 1 で許可したデータベースだけが見えていることをユーザーと一緒に確認する。**想定より多くのデータベースが見える場合は、ポリシーの範囲が広すぎる**ので Step 1 に戻る。

---

## できること / できないこと

**できる**（19 ツール）

- データベース・テーブル・カラム定義の確認
- 読み取り専用 SQL の実行（Trino 方言、TD の UDF 利用可）
- CDP の親セグメント／セグメント／アクティベーションの参照、セグメント定義 SQL の取得
- Workflow のプロジェクト・ワークフロー・セッション・実行履歴・タスクログの参照

**できない**（意図的に塞いである）

- `INSERT` / `UPDATE` / `DELETE` / `CREATE` / `DROP` / `ALTER` などの書き込み SQL
- ワークフローの停止・リトライ（`kill_attempt` / `retry_session` / `retry_attempt`）

書き込みが必要になった場合、この拡張機能の設定では有効化できない。`tdx` CLI や TD コンソールなど別の経路を使うよう案内する。

---

## クエリを書くときの注意

- **方言は Trino**。Hive SQL ではない
- 大きいテーブルには必ず時間範囲を付ける: `TD_INTERVAL(time, '-30d/now')`
- `query` ツールは既定で **40 行**しか返さない。必要なら `limit` を指定する（最大 10000）。ただしこれは返す行数の上限であって**スキャン量の上限ではない**ので、集計はできるだけ SQL 側で完結させる
- 実行したクエリは TD 側のジョブ履歴に残る。拡張機能側にクエリログは保存されない

---

## トラブルシューティング

**ツールが会話に出てこない**

拡張機能は会話の開始時に読み込まれる。インストール後は**新しい会話を開始**する。それでも出ない場合は 設定 → 拡張機能 で有効になっているか確認。

**`No API key is configured`**

設定 → 拡張機能 → Treasure Data (read-only) で API キーが空欄。Step 4 をやり直す。

**`TD_SITE "..." is not a known region`**

リージョン ID の綴り間違い。`us01` / `jp01` / `eu01` / `ap02` / `ap03` のいずれか。

**認証エラーが返る**

- Write-only Key を貼っていないか確認する（クエリには Master Key が必要）
- リージョンが合っているか確認する。別リージョンのキーでは認証できない
- TD 側でキーが失効していないか確認する

**`This connection is read-only.`**

書き込み SQL を投げている。意図通りの動作。読み取りのつもりで出た場合は SQL を見直す（`SELECT` / `WITH` / `SHOW` / `DESCRIBE` / `EXPLAIN` で始まる必要がある）。

**データベースが 1 つも見えない**

Step 1 のポリシーがそのユーザーに割り当たっていない可能性が高い。TD コンソールで確認してもらう。

---

## 運用

- **キーのローテーション**: 90 日ごと、または組織のポリシーに従って新しいキーを発行し、Step 4 で差し替えてから旧キーを失効させる
- **退職・異動時**: TD 側でユーザーを無効化すればこの拡張機能も使えなくなる
- **アンインストール**: 設定 → 拡張機能 から削除する。キーチェーン上の値も一緒に削除される

---

## 実装の背景（聞かれたら説明する）

この拡張機能は Treasure Data 公式の MCP サーバー (`@treasuredata/mcp-server`, Apache-2.0) をそのまま同梱し、起動前に読み取り専用の枷をかけている。公式サーバーの読み取り専用判定は行コメント (`--`) しか除去しないため、ブロックコメントで書き込みを偽装できる（`/* x */ DROP TABLE t` が UNKNOWN と判定されて通る）。同梱しているランチャーは、ブロックコメント・行コメント・文字列リテラルを除去したうえで再判定し、失敗時は起動を拒否する。

ただしこれはあくまで多層防御の一層でしかない。**実効的な権限管理は Step 1 の TD 側のポリシー**であり、そこを省略した構成は推奨しない。

詳細は同ディレクトリの `README.md` と `src/server/index.js` を参照。
