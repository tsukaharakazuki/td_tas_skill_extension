---
name: td-claude2tdx-connect
description: 'Use whenever the user wants to query, inspect, or operate Treasure Data from Claude — running SQL, listing databases or tables, checking schemas, CDP segments, journeys, Engage, workflows, jobs, or schedules. Also use immediately after this plugin is installed, and whenever Treasure Data access needs to be set up or is failing. Triggers on phrases like "TDのDBを教えて", "TDでクエリして", "テーブルの中身見せて", "セグメントを確認して", "ワークフロー流して", "TDに繋ぎたい", "TDのセットアップして", "td-claude2tdx-connect", "query Treasure Data", "list TD databases", "connect Claude to Treasure Data".'
---

# Treasure Data に接続して操作する

作業フォルダのキーファイルで認証し、Treasure Data を直接操作する。接続方式は2つ。

| 方式 | 中身 | 通信先 | 向いている場面 |
|---|---|---|---|
| **A. td-api.sh（既定）** | 同梱の bash スクリプト。curl で TD の REST API を呼ぶ | `*.treasuredata.com` / `*.treasuredata.co.jp` のみ | npm を許可できない環境。参照中心の利用 |
| **B. tdx（検証済み一式）** | 公式 CLI tdx を、事前に検証・固定したオフライン一式から展開 | 同上（npm には繋がない） | ジャーニー・Engage など tdx でしか扱いにくい操作が要るとき |

**`registry.npmjs.org` の許可は前提にしない。** セッションから npm に繋いでパッケージを取りに行く手順は、ユーザーが明示的に求めた場合を除いて案内しない。

**ブラウザで TD コンソールを開く、ユーザーに `td db:list` の結果を貼ってもらう、といった代替手段を提案しないこと。** 以下の手順で直接クエリできる。

---

## 作業フォルダの構成

すべてを1つの作業フォルダに閉じ込める。既定の名前は **`TreasureAI`**。

```
TreasureAI/
├── tdx_key.txt                 1行目: API キー / 2行目: リージョン（任意、既定 us01）
├── td-api.sh                   方式A。プラグイン同梱のものを置く
├── tdx-bundle-<ver>.tgz        方式B を使う場合のみ。検証済みのオフライン一式
├── tdx-bundle-<ver>.tgz.sha256
└── runtime/                    方式B の展開先
```

---

## このスキルが呼ばれたら

**まず Step 1 を実行する。** 「セットアップしますか？」と聞かない。確認してから状況を報告する。インストール直後に呼ばれた場合も同じ。

## Step 1: 状態を確認する

`device_bash` で1回実行する。

```bash
echo "--- connected folders ---"; ls "$HOME/mnt/" 2>/dev/null
echo "--- key file ---";  find "$HOME/mnt" -maxdepth 4 -name 'tdx_key.txt' -size +0 2>/dev/null
echo "--- td-api.sh ---"; find "$HOME/mnt" -maxdepth 4 -name 'td-api.sh' 2>/dev/null
echo "--- tdx ---";       find "$HOME/mnt" -maxdepth 5 \( -path '*/runtime/bin/tdx' -o -name 'tdx-bundle-*.tgz' \) 2>/dev/null
echo "--- network ---";   curl -s -o /dev/null -w '%{http_code}\n' --max-time 15 https://api.treasuredata.com/v3/system/server_status
```

| 結果 | 次 |
|---|---|
| キーが無い | Step 2 |
| 接続フォルダが1つも無い | Step 2 の「未接続の場合」 |
| network が `200` 以外 | ネットワーク許可を案内（`references/troubleshooting.md`）。キーの準備は並行して進めてよい |
| キーあり・`runtime/bin/tdx` か `tdx-bundle-*.tgz` あり | Step 3B |
| キーあり・それ以外 | Step 3A |

以降、キーファイルのあるディレクトリを `<WORKDIR>` と呼ぶ。

## Step 2: 作業フォルダを決めてキーを置いてもらう

**フォルダをユーザーに確認してから作る。勝手に決めない。** 既定は `TreasureAI`。ユーザーが別の名前を希望すればそれに従う。

**接続フォルダがある場合。** その中にサブフォルダを作ることを勧める。既存のフォルダ直下にファイルを散らかさない。

> 接続されている `<フォルダ名>` の中に `TreasureAI` というフォルダを作って、そこに API キーと接続用スクリプトをまとめます。この名前で進めてよいですか？

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
- 作業フォルダが git リポジトリの中なら、`.gitignore` に `tdx_key.txt`・`runtime/`・`tdx-bundle-*` を追加し、`git check-ignore -v tdx_key.txt` で除外を確認する

## Step 3A: td-api.sh を置く（既定）

このスキルのディレクトリにある `td-api.sh` を `<WORKDIR>/td-api.sh` として置く（クラウド側で outputs にコピーし、`device_commit_files` で書き込む）。置いたら実行権を付けて疎通を確認する。

```bash
chmod +x "<WORKDIR>/td-api.sh"
TD_WORKDIR="<WORKDIR>" "<WORKDIR>/td-api.sh" status
```

`auth: OK（見えるデータベース: N 件）` が出れば完了。**中身は改変しない。** 同梱版をそのまま置く。

## Step 3B: tdx を検証済み一式から展開する

`tdx-bundle-*.tgz` と `.sha256` が作業フォルダにある場合のみ。`setup-tdx.sh` と同じ処理を行う。

```bash
cd "<WORKDIR>"
want="$(awk '{print $1}' tdx-bundle-*.tgz.sha256)"; got="$(sha256sum tdx-bundle-*.tgz | awk '{print $1}')"
[ "$want" = "$got" ] && mkdir -p runtime && tar xzf tdx-bundle-*.tgz -C runtime && runtime/bin/tdx --version
```

**SHA-256 が一致しなければ展開しない。** ユーザーに一式の作り直しを依頼する。

一式が無く、ユーザーが tdx を使いたいと言った場合は、`scripts/build-tdx-bundle.sh` を **npm に到達できる管理端末（または社内 npm ミラー）で** 実行してもらうよう案内する。セッションから npm に繋ぐ方法は勧めない。

## Step 4: 実行する

### 方式A（td-api.sh）

```bash
export TD_WORKDIR="<WORKDIR>"; S="<WORKDIR>/td-api.sh"
$S databases
$S tables <db>
$S describe <db> <table>
$S query <db> "SELECT ... LIMIT 100"            # 結果は CSV。既定で先頭200行
$S query <db> "<SQL>" --out "<WORKDIR>/out.csv" # 全件をファイルへ
$S job-status <job_id> / $S job-result <job_id>
$S parent-segments / $S segments <parent_segment_id>
$S wf-projects / $S wf-workflows <project_id> / $S wf-attempts 20
$S get <api|cdp|workflow> /<path>               # 上に無い参照系 API
```

- `query` は既定で **参照系 SQL のみ**通す。書き込み系（INSERT / DELETE / DROP / CREATE など）は、ユーザーの明示的な了承を得てから `TD_ALLOW_WRITE=1` を付ける
- `query` は約150秒待って終わらなければジョブ ID を返す。その後 `job-status` → `job-result`
- `device_bash` の上限（180秒）を超えそうな処理は `--wait` を短くして分割する

### 方式B（tdx）

毎回このプレフィックスを付ける。

```bash
export PATH="<WORKDIR>/runtime/bin:$PATH"
export TDX_API_KEY="$(sed -n '1p' "<WORKDIR>/tdx_key.txt" | tr -d '[:space:]')"
export TDX_SITE="$(sed -n '2p' "<WORKDIR>/tdx_key.txt" | tr -d '[:space:]')"; export TDX_SITE="${TDX_SITE:-us01}"
tdx --site "$TDX_SITE" <コマンド>
```

コマンドとクエリの流儀は `references/tdx-commands.md` を読む。

### 共通

**キーの中身を表示しない。** `cat tdx_key.txt` や `echo $TDX_API_KEY` を実行しない。確認が要るなら長さだけ見る（`td-api.sh status` が表示する）。

詰まったら `references/troubleshooting.md`。

---

## 権限の扱い

**実効的な権限境界は、キーが指す Treasure Data ユーザーの権限だけ。** td-api.sh の参照系ガードは誤操作防止であり、セキュリティ境界ではない。

- **本番データを変更する操作の前に、必ずユーザーに確認を取る。** テーブルの削除・更新、セグメント定義やジャーニーの変更、Engage の配信、スケジュールの改変が該当する
- `TD_ALLOW_WRITE=1`、tdx の `-y` / `--yes` を自分の判断で付けない。ユーザーが明示したときだけ
- tdx の `auth login` / `auth logout` / `profile` / `mcp` / `upgrade` / `claude` / `codex` は実行しない。`upgrade` は npm に繋ぎにいく。`tdx auth status` は参照のみなので実行してよい
- `tdx user` / `policy` の**変更**は、ユーザーが明示的に頼んだときだけ

初回の一覧で組織の全データベースが見えている場合、そのキーはポリシーで絞られていない。その事実を1行伝え、用途を絞った専用ユーザーのキーに差し替える選択肢を添える。繰り返さない。

---

## 詰まったときの要点

**`接続できませんでした` / `403 CONNECT`** — Claude のネットワークアクセス設定で `*.treasuredata.com` と `*.treasuredata.co.jp` が許可されていない。**npm の許可は不要。**

**`認証失敗 (401)`** — キーかリージョン違い。`tdx_key.txt` の2行目を確認。

**`tdx: command not found`** — `device_bash` は毎回新しいシェル。コマンドごとに PATH を付ける。

---

## PC と繋がっていない場合

`device_bash` が無いセッションでも、クラウド側のシェルで td-api.sh が動く。ただしキーファイルを読めないため、ユーザーに添付してもらう必要がある。添付されたファイルは `/mnt/user-data/uploads/` から読み、`TD_WORKDIR` にそのディレクトリを指定して使う。**中身を出力しない。** この経路を使ったら、セッション後にキーを無効化して作り直すよう伝える。

渋る場合は無理に勧めない。PC を繋ぐ方が安全だと伝える。
