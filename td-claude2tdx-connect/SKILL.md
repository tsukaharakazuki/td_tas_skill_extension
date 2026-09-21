---
name: td-claude2tdx-connect
description: 'Use whenever the user wants to query, inspect, or operate Treasure Data from Claude — running SQL, listing databases or tables, checking schemas, CDP segments, journeys, Engage, workflows, jobs, or schedules. Also use immediately after this plugin is installed, and whenever Treasure Data access needs to be set up or is failing. Triggers on phrases like "TDのDBを教えて", "TDでクエリして", "テーブルの中身見せて", "セグメントを確認して", "ワークフロー流して", "TDに繋ぎたい", "TDのセットアップして", "td-claude2tdx-connect", "query Treasure Data", "list TD databases", "connect Claude to Treasure Data".'
---

# Treasure Data に接続して操作する

`tdx` CLI を作業フォルダに導入し、同じフォルダのキーファイルで認証して Treasure Data を直接操作する。

**ブラウザで TD コンソールを開く、ユーザーに `td db:list` の結果を貼ってもらう、といった代替手段を提案しないこと。** 不要で、以下の手順で直接クエリできる。

---

## 作業フォルダの構成

すべてを1つの作業フォルダに閉じ込める。既定の名前は **`TreasureAI`**。

```
TreasureAI/
├── tdx_key.txt     1行目: API キー / 2行目: リージョン（任意、既定 us01）
└── runtime/        tdx 本体。セッションをまたいで残るので再インストール不要
```

`runtime/` を接続フォルダ内に置くのが要点。セッション環境のホームは使い捨てだが、接続フォルダは残るため、2回目以降のセットアップが不要になる。

---

## このスキルが呼ばれたら

**まず Step 1 を実行する。** 「セットアップしますか？」と聞かない。確認してから状況を報告する。インストール直後に呼ばれた場合も同じ。

## Step 1: 状態を確認する

`device_bash` で1回実行する。

```bash
echo "--- connected folders ---"; ls "$HOME/mnt/" 2>/dev/null
echo "--- key file ---";  find "$HOME/mnt" -maxdepth 4 -name 'tdx_key.txt' -size +0 2>/dev/null
echo "--- runtime ---";   find "$HOME/mnt" -maxdepth 5 -path '*/runtime/bin/tdx' 2>/dev/null
```

| 結果 | 次 |
|---|---|
| キーと runtime が揃っている | Step 4 |
| キーはある・runtime が無い | Step 3 |
| キーが無い | Step 2 |
| 接続フォルダが1つも無い | Step 2 の「未接続の場合」 |

以降、キーファイルのあるディレクトリを `<WORKDIR>` と呼ぶ。

## Step 2: 作業フォルダを決めてキーを置いてもらう

**フォルダをユーザーに確認してから作る。勝手に決めない。** 既定は `TreasureAI`。ユーザーが別の名前を希望すればそれに従う。

**接続フォルダがある場合。** その中にサブフォルダを作ることを勧める。既存のフォルダ直下にファイルを散らかさない。

> 接続されている `<フォルダ名>` の中に `TreasureAI` というフォルダを作って、そこに API キーと tdx をまとめます。この名前で進めてよいですか？

接続フォルダが複数あるなら、どれの下に作るかも聞く。承諾を得たら作成する。

```bash
mkdir -p "$HOME/mnt/<接続フォルダ>/TreasureAI"
: > "$HOME/mnt/<接続フォルダ>/TreasureAI/tdx_key.txt"
chmod 600 "$HOME/mnt/<接続フォルダ>/TreasureAI/tdx_key.txt"
```

空のファイルまで作ってから、ユーザーに中身を書いてもらう。**Finder 上のパスで案内する**（`~/mnt/...` はユーザーには見えない）。

> `<フォルダ名>` → `TreasureAI` → `tdx_key.txt` を開いて、1行目に Treasure Data の API キーを貼って保存してください。リージョンが `us01` 以外なら、2行目にリージョン名（`ap01` など）を書いてください。

**未接続の場合。** Claude デスクトップアプリの「フォルダを追加」で作業用フォルダを接続してもらう。新規に作るなら `TreasureAI` を勧める。接続されたら上の手順に戻る。

**守ること:**

- **隠しファイル名（`.tdx_key` など）を提案しない。** Finder に表示されず、ユーザーが開けない
- キーをチャットに貼らせない。会話履歴に残る。貼られてしまったら、そのキーを無効化して作り直すよう伝える
- 作業フォルダが git リポジトリの中なら、`.gitignore` に `tdx_key.txt` と `runtime/` を追加し、`git check-ignore -v tdx_key.txt` で除外を確認する

## Step 3: tdx を作業フォルダに入れる

`timeout_ms` を 180000 にして実行する。60秒ほどかかる。約 60MB。

```bash
npm i -g --prefix "<WORKDIR>/runtime" @treasuredata/tdx >/dev/null 2>&1
export PATH="<WORKDIR>/runtime/bin:$PATH"
tdx --version
```

リポジトリを接続している場合は、同梱の `setup-tdx.sh` を `source` しても同じ結果になる。

## Step 4: 実行する

毎回このプレフィックスを付ける。

```bash
export PATH="<WORKDIR>/runtime/bin:$PATH"
export TDX_API_KEY="$(sed -n '1p' "<WORKDIR>/tdx_key.txt" | tr -d '[:space:]')"
export TDX_SITE="$(sed -n '2p' "<WORKDIR>/tdx_key.txt" | tr -d '[:space:]')"; export TDX_SITE="${TDX_SITE:-us01}"
tdx --site "$TDX_SITE" <コマンド>
```

**キーの中身を表示しない。** `cat tdx_key.txt` や `echo $TDX_API_KEY` を実行しない。確認が要るなら `${#TDX_API_KEY}` で長さだけ見る。

コマンドとクエリの流儀は `references/tdx-commands.md` を読む。詰まったら `references/troubleshooting.md`。

---

## 権限の扱い

**この構成には安全装置が無い。** `tdx` を直接実行するため、参照も書き込みも同じように通る。実効的な権限境界は、キーが指す Treasure Data ユーザーの権限だけ。

- **本番データを変更する操作の前に、必ずユーザーに確認を取る。** テーブルの削除・更新、セグメント定義やジャーニーの変更、Engage の配信、スケジュールの改変が該当する
- `-y` / `--yes` を自分の判断で付けない。ユーザーが明示したときだけ
- `tdx auth` / `profile` / `mcp` / `upgrade` / `claude` / `codex` は実行しない。認証情報を壊す、プロセスが返らない、といった実害がある
- `tdx user` / `policy` の**変更**は、ユーザーが明示的に頼んだときだけ

初回の `tdx databases` で組織の全データベースが見えている場合、そのキーはポリシーで絞られていない。その事実を1行伝え、用途を絞った専用ユーザーのキーに差し替える選択肢を添える。繰り返さない。

---

## 詰まったときの要点

`references/troubleshooting.md` に症状別の対処がある。頻度が高いもの:

**`403 CONNECT` / 到達できない** — Claude のネットワークアクセス設定で `*.treasuredata.com` と `*.treasuredata.co.jp` が許可されていない。npm は既定で通るため、インストールだけ成功して認証で落ちる形で出る。

**`No credential found`** — 変数名が違う。`TD_API_KEY` ではなく `TDX_API_KEY`。

**`tdx: command not found`** — `device_bash` は毎回新しいシェル。コマンドごとに `export PATH="<WORKDIR>/runtime/bin:$PATH"` を付ける。runtime が消えたわけではないので、まず PATH を疑う。

---

## PC と繋がっていない場合

`device_bash` が無いセッションでも、クラウド側のシェルで同じ手順が動く。ただしキーファイルを読めないため、ユーザーに添付してもらう必要がある。添付されたファイルは `/mnt/user-data/uploads/` から読み、環境変数に入れて使う。**中身を出力しない。** この経路を使ったら、セッション後にキーを無効化して作り直すよう伝える。

渋る場合は無理に勧めない。PC を繋ぐ方が安全だと伝える。
