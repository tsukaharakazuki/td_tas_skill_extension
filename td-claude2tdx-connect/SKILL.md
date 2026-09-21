---
name: td-claude2tdx-connect
description: 'Use when the user wants Claude to operate Treasure Data through the tdx CLI — running workflows, managing CDP segments and journeys, Engage campaigns, jobs, or any write operation — or when they need help installing, configuring, or troubleshooting the tdx desktop extension (.mcpb). Triggers on phrases like "tdxをClaudeから使いたい", "tdxの設定", "Claudeからワークフローを実行したい", "セグメントをClaudeで操作したい", "TDに書き込みたい", "td-claude2tdx-connect", "権限モードを変えたい", "set up tdx for Claude".'
---

# Claude → Treasure Data (tdx) 接続セットアップ

Treasure AI の公式 CLI である **tdx** を Claude から使えるようにする対話型セットアップ。`td-claude2tdx-connect` 拡張機能 (`.mcpb`) を各ユーザーの PC にインストールする。

API キーはユーザーの PC の OS キーチェーンに保存され、Treasure Data への通信もユーザーの PC から直接行われる。

---

## ⚠️ この拡張機能の性格を最初に伝える

`td-claude2td-connect`（参照専用）とは**権限の性格が根本的に異なる**。ユーザーが混同したまま進まないよう、Step 1 の前に必ず伝えること。

- tdx の MCP サーバーが公開するツールは実質 1 つ (`tdx_run`) で、**任意の tdx コマンドを実行する**
- したがって「このツールだけ許可する」という細かい制御が効かない
- **実効的な権限境界は Treasure Data 側のポリシー**であり、拡張機能側の権限モードはその手前の安全装置にすぎない

この拡張機能には権限モードがあるが、**API キーの持ち主が本番データを消せる権限を持っていれば、モードを変えるだけでは守れない**（モードは設定画面でユーザー自身が変更できる）。TD 側の権限設計を省略させないこと。

---

## 前提

- **Claude デスクトップアプリ**（macOS または Windows）
- **Node.js 22.12 以上**が必要。デスクトップアプリ同梱の Node がこれを満たさない場合は起動に失敗するので、その場合は Node 22 以上をインストールしてもらう
- Treasure Data のアカウント

---

## 実行フロー

Step 1 → 6 の全体像を最初に伝えてから、1 ステップずつ進める。

---

### Step 1: 権限モードを決める

**ここを最初にやる。** モードが決まらないと、Step 2 で作るべき TD ユーザーの権限も決まらない。

ユーザーに「Claude に何をさせたいか」を聞き、下表から選んでもらう。

| モード | 使えるもの | 向いている用途 |
|---|---|---|
| `readonly` | 参照コマンドのみ。SQL も参照のみ | データ調査、スキーマ確認、セグメント定義の確認 |
| `operate` | 上記＋ジョブ・ワークフロー・スケジュールの実行/再実行/停止。定義変更は不可、SQL は参照のみ | 日次運用、ワークフローの実行とリカバリ |
| `full` | 全コマンド（既定） | 開発、CDP 定義の構築・変更 |

**迷っている場合は `readonly` から始めるよう勧める。** モードは設定画面でいつでも広げられる。「とりあえず full」は、Step 2 の権限設計を曖昧にしたまま進む口実になりやすい。

どのモードでも常に禁止されるもの: `auth` / `profile` / `profiles` / `mcp` / `upgrade` / `claude` / `codex`。

ユーザー管理 (`user`) とアクセスポリシー (`policy`) の**変更**は、モードとは別の「管理コマンドを許可する」スイッチで制御する。既定は無効。権限そのものを書き換えられるため、有効化は明確な理由があるときだけにするよう伝える。参照（`users`、`policy list`）は無効のままでも可能。

---

### Step 2: Treasure Data 側でユーザーとポリシーを用意する

Step 1 で決めたモードに見合う権限のユーザーを作る。**既存の管理者アカウントのキーを使わせない。**

1. TD コンソールの **Control Panel → Users** で用途専用のユーザーを作成
2. **Control Panel → Policies** でポリシーを作成し、対象データベースと操作範囲を Step 1 のモードに合わせる
   - `readonly` → 参照権限のみ、対象 DB も必要最小限に
   - `operate` → 上記＋ワークフロー実行に必要な権限
   - `full` → 作業対象のプロジェクト／データベースに限定する。全 DB を対象にしない
3. そのポリシーをユーザーに割り当てる
4. そのユーザーで **My Settings → API Keys** から **Master Key** を取得

**リージョン ID** も控えてもらう:

| コンソールの URL | リージョン ID |
|---|---|
| `console.treasuredata.co.jp` | `jp01` |
| `console.treasuredata.com` / `console-next.us01...` | `us01` |
| `console.eu01.treasuredata.com` | `eu01` |
| `console.ap02.treasuredata.com` | `ap02` |
| `console.ap03.treasuredata.com` | `ap03` |

> すでに PC で `tdx profile create` 済みのユーザーは、API キーの代わりにプロファイル名を使える（Step 4 参照）。その場合でも、そのプロファイルが指す TD ユーザーの権限が適切かは確認してもらうこと。

---

### Step 3: 拡張機能をダウンロードする

```
https://github.com/tsukaharakazuki/td_tas_skill_extension/raw/main/td-claude2tdx-connect/dist/td-claude2tdx-connect-0.1.0.mcpb
```

ファイル名 `td-claude2tdx-connect-0.1.0.mcpb`（約 8 MB）。ZIP 形式なので、ブラウザの警告は無視して保存して問題ない。

---

### Step 4: インストールして設定する

ダウンロードしたファイルをダブルクリック。開かない場合は **設定 → 拡張機能 → 詳細設定 → 拡張機能をインストール…**。

設定画面で以下を入力してもらう:

| 項目 | 入力する値 |
|---|---|
| **Treasure Data API キー** | Step 2 で取得した Master Key。プロファイルを使う場合は空欄 |
| **tdx プロファイル名** | この PC で `tdx profile create` 済みの場合のみ。指定するとこちらが優先される |
| **リージョン** | Step 2 で確認したリージョン ID（既定 `jp01`） |
| **権限モード** | Step 1 で決めた `readonly` / `operate` / `full` |
| **管理コマンドを許可する** | 通常は無効のまま |

API キーの入力欄はマスクされ、値は OS のキーチェーンに保存される。

**ユーザーに API キーを会話へ貼らせないこと。** 貼られてしまった場合は、そのキーを TD 側で失効させて作り直すよう伝える。

入力後、拡張機能を有効化してもらう。

---

### Step 5: 疎通確認

新しい会話を開始してもらい（拡張機能は会話開始時に読み込まれる）、こちらから確認する。

```
tdx_run(args: ["databases"])
```

Step 2 で許可したデータベースだけが見えていることをユーザーと一緒に確認する。**想定より多く見える場合はポリシーが広すぎる**ので Step 2 に戻る。

---

### Step 6: モードの効きを確認する

`readonly` または `operate` を選んだ場合、意図どおり止まることを一度見せておく。

```
tdx_run(args: ["table", "create", "<存在しないDB>.tmp_check"])
```

「このモードでは許可されていない」という趣旨のエラーが返れば正しい。`full` の場合はこの確認は不要。

---

## 使い方のコツ

- **コマンドが分からないときは `tdx_search` を先に使う。** 自然文で該当コマンドを探せる
- **破壊的な操作の前に `--dry-run` を付ける。** 多くのコマンドが対応している
- **`-y` / `--yes` を安易に付けない。** 確認プロンプトを飛ばすフラグなので、ユーザーの承認なしに付けないこと
- **出力は `--json` が扱いやすい。** 既定は人間向けの表形式
- **重いクエリは `job submit` で投げる。** `tdx_run` は 15 分でタイムアウトする
- **クエリには時間範囲を付ける。** `TD_INTERVAL(time, '-30d/now')`
- 実行内容は TD 側のジョブ履歴に残る

---

## 2つの拡張機能の使い分け

| | td-claude2td-connect | td-claude2tdx-connect |
|---|---|---|
| ツール | 19個、すべて参照系 | 実質 1 個（任意の tdx コマンド） |
| 書き込み | 構造的に不可能 | モード次第で可能 |
| 導入の手軽さ | 入れるだけ | 権限設計が前提 |
| 向く相手 | データを見たい人 | 運用・開発する人 |

参照しかしないなら `td-claude2td-connect` の方が安全。両方入れても競合しないが、**同時に有効にすると同じ操作に 2 経路ができて挙動が読みにくくなる**ので、用途が固まっているなら片方だけ有効にするよう勧める。

---

## トラブルシューティング

**ツールが会話に出てこない**

拡張機能は会話開始時に読み込まれる。インストール後は新しい会話を開始する。設定 → 拡張機能 で有効になっているかも確認。

**`No credentials configured`**

API キーもプロファイル名も空欄。Step 4 をやり直す。

**`Unknown permission mode "..."`**

権限モードの綴り間違い。`full` / `operate` / `readonly` のいずれか。

**起動しない / Node のバージョンエラー**

tdx は Node 22.12 以上を要求する。Node 22 以上をインストールしてもらう。

**`"..." is not available through this extension in any mode`**

`auth` / `profile` / `upgrade` などの常時禁止コマンド。仕様どおり。プロファイルの作成や認証はターミナルで `tdx` を直接使ってもらう。

**`This connection runs in "readonly" mode...`**

モードの制限。必要なら設定 → 拡張機能 でモードを広げる。ただし **TD 側の権限も見直すこと**。モードだけ広げても、TD ユーザーに権限がなければ結局失敗する（逆に、TD ユーザーに権限がありすぎる状態でモードだけ広げるのが一番危ない）。

**認証エラー**

- Write-only Key ではなく Master Key か
- リージョンが合っているか
- プロファイル指定の場合、そのプロファイルがこの PC に存在するか（`tdx profiles` で確認）

---

## 運用

- **キーのローテーション**: 90 日ごと、または組織のポリシーに従って差し替える
- **モードの見直し**: 用途が変わったら設定画面で変更する。「一時的に full にして戻し忘れる」が起きやすいので、作業後に戻すようユーザーに促す
- **アンインストール**: 設定 → 拡張機能 から削除。キーチェーン上の値も削除される

---

## 実装の背景（聞かれたら説明する）

`tdx mcp` は `tdx_run` / `tdx_search` / `work_create_item` の 3 ツールを公開し、`tdx_run` は任意の tdx コマンドを実行する（tdx 自身がブロックするのは `auth` / プロファイル管理 / `mcp` のみ）。読み取り専用モードは存在しない。

この拡張機能は tdx を無改変で同梱し、**MCP の JSON-RPC を中継するプロキシ**として権限モードを適用している。tdx は月次のカレンダーバージョンで更新され、配布物も難読化されているため、内部に手を入れる実装は壊れやすい。プロトコル層で処理することで tdx の実装から独立させている。

`readonly` / `operate` での SQL 検証は、参照専用拡張機能と同じ方式（ブロックコメント・行コメント・文字列リテラルを除去してから判定）を使っている。

詳細は同ディレクトリの `README.md` と `src/server/policy.js` を参照。
