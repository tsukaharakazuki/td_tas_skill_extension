---
name: td-claude2tdx-connect
description: 'Use whenever the user wants to query, inspect, or operate Treasure Data from Claude — running SQL, listing databases or tables, checking schemas, CDP segments, journeys, Engage, workflows, jobs, or schedules. Also use immediately after this plugin is installed, and whenever Treasure Data access needs to be set up or is failing. Triggers on phrases like "TDのDBを教えて", "TDでクエリして", "テーブルの中身見せて", "セグメントを確認して", "ワークフロー流して", "TDに繋ぎたい", "TDのセットアップして", "td-claude2tdx-connect", "query Treasure Data", "list TD databases", "connect Claude to Treasure Data".'
---

# Treasure Data に接続して操作する

公式 CLI `tdx` を作業フォルダに導入し、同じフォルダのキーファイルで認証して Treasure Data を操作する。tdx の全コマンド（SQL、CDP、ジャーニー、Engage、ワークフローの push / run など）を使う前提。

**導入方法はお客様の環境によって変わる。** 環境を診断して導入プランを提示し、お客様が選んだプランで導入・検証する。選んだプランは作業フォルダの `tdx_setup.conf` に記録され、次回以降はそれに従う。

| プラン | 導入元 | セッションに必要な通信許可 |
|---|---|---|
| **A. npm 直接** | registry.npmjs.org（版固定） | TD ドメイン + `registry.npmjs.org` |
| **B. 社内ミラー** | お客様の npm ミラー（版固定） | TD ドメイン + ミラーのホスト |
| **C. オフライン一式** | 管理端末で作った一式（SHA-256 照合） | TD ドメインのみ |
| **D. curl のみ** | tdx を入れず `td-api.sh` を使う | TD ドメインのみ |

A〜C は Node.js 22.12 以上が必要。D は機能限定（参照・SQL・ワークフロー参照が中心）で、A〜C が使えないときの代替。

**ブラウザで TD コンソールを開く、ユーザーに `td db:list` の結果を貼ってもらう、といった代替手段を提案しないこと。**

---

## 作業フォルダの構成

既定の名前は **`TreasureAI`**。

```
TreasureAI/
├── tdx_key.txt          1行目: API キー / 2行目: リージョン（任意、既定 us01）
├── tdx_setup.conf       選んだプランの記録（setup-tdx.sh install が書く）
├── setup-tdx.sh         診断・導入・検証スクリプト（プラグイン同梱のものを置く）
├── td-api.sh            プラン D 用（同上）
├── tdx-bundle-*.tgz     プラン C 用の一式と .sha256
└── runtime/             tdx の導入先。セッションをまたいで残る
```

---

## このスキルが呼ばれたら

**まず Step 1 を実行する。** 「セットアップしますか？」と聞かない。インストール直後に呼ばれた場合も同じ。

## Step 1: 状態を確認する

`device_bash` で1回実行する。

```bash
echo "--- connected folders ---"; ls "$HOME/mnt/" 2>/dev/null
echo "--- key file ---"; find "$HOME/mnt" -maxdepth 4 -name 'tdx_key.txt' -size +0 2>/dev/null
echo "--- setup conf ---"; find "$HOME/mnt" -maxdepth 4 -name 'tdx_setup.conf' -exec cat {} \; 2>/dev/null
```

| 結果 | 次 |
|---|---|
| キーが無い / 接続フォルダが無い | Step 2 |
| キーあり・`tdx_setup.conf` なし | Step 3（プランを提示） |
| キーあり・`tdx_setup.conf` あり | Step 5（検証）。合格なら Step 6 へ。不合格なら原因に応じて Step 3 からやり直す |

以降、キーファイルのあるディレクトリを `<WORKDIR>` と呼ぶ。

## Step 2: 作業フォルダを決めてキーを置いてもらう

**フォルダをユーザーに確認してから作る。勝手に決めない。** 既定は `TreasureAI`。

**接続フォルダがある場合。** その中にサブフォルダを作ることを勧める。

> 接続されている `<フォルダ名>` の中に `TreasureAI` というフォルダを作って、そこに API キーと tdx をまとめます。この名前で進めてよいですか？

承諾を得たら作成する。

```bash
mkdir -p "$HOME/mnt/<接続フォルダ>/TreasureAI"
: > "$HOME/mnt/<接続フォルダ>/TreasureAI/tdx_key.txt"
chmod 600 "$HOME/mnt/<接続フォルダ>/TreasureAI/tdx_key.txt"
```

**Finder 上のパスで案内する**（`~/mnt/...` はユーザーには見えない）。

> `<フォルダ名>` → `TreasureAI` → `tdx_key.txt` を開いて、1行目に Treasure Data の API キーを貼って保存してください。リージョンが `us01` 以外なら、2行目にリージョン名（`ap01` など）を書いてください。

**未接続の場合。** Claude デスクトップアプリの「フォルダを追加」で作業用フォルダを接続してもらう。

**守ること:**

- **隠しファイル名（`.tdx_key` など）を提案しない。** Finder に表示されない
- キーをチャットに貼らせない。貼られてしまったら、そのキーを無効化して作り直すよう伝える
- 作業フォルダが git リポジトリの中なら、`.gitignore` に `tdx_key.txt`・`tdx_setup.conf`・`runtime/`・`tdx-bundle-*` を追加する

## Step 3: 環境を診断してプランを提示する

このスキルのディレクトリにある `setup-tdx.sh` と `td-api.sh` を `<WORKDIR>` に置く（クラウド側で outputs にコピーし、`device_commit_files` で書き込む）。中身は改変しない。

お客様が社内ミラーを使うと分かっている場合は、`NPM_REGISTRY=<URL>` を付けて診断する。

```bash
cd "<WORKDIR>" && chmod +x setup-tdx.sh td-api.sh
TD_WORKDIR="<WORKDIR>" bash setup-tdx.sh plan
# 社内ミラーがある場合
TD_WORKDIR="<WORKDIR>" NPM_REGISTRY="<URL>" bash setup-tdx.sh plan
```

出力の `[OK]` / `[NG]` と「選べるプラン」を、**表にしてユーザーに提示する**。各プランについて「利用可否」「理由」「お客様側で必要な設定」を並べ、`RECOMMENDED=` のプランを推奨として示す。**`AskUserQuestion` でプランを選んでもらう。** 推奨を先頭に置き「(推奨)」を付ける。利用不可のプランも、必要な設定（下表）を添えて選択肢に含めてよい。

| 利用不可の理由 | お客様側で必要な設定 |
|---|---|
| Treasure Data に到達できない | Claude のネットワーク許可に `*.treasuredata.com` / `*.treasuredata.co.jp` |
| Node.js が無い・古い | セッション環境に Node.js 22.12 以上。用意できなければプラン D |
| registry.npmjs.org の許可が必要（A） | ネットワーク許可に `registry.npmjs.org` |
| ミラーが必要（B） | ミラー URL を教えてもらい、そのホストをネットワーク許可に追加。認証が要るミラーなら `.npmrc` の設定 |
| 一式が必要（C） | 管理端末で `scripts/build-tdx-bundle.sh` を実行し、`tdx-bundle-*.tgz` と `.sha256` を作業フォルダに置く |

ユーザーが「お客様の環境に合わせて」と言った場合は、お客様のネットワーク方針（npm を許可できるか、ミラーがあるか）を聞いてからプランを決める。**npm を許可できない環境で A を勧めない。**

選ばれたプランが今は利用不可なら、必要な設定を案内して待つ。設定後に `plan` を再実行して `○` になったことを確認してから Step 4。

## Step 4: 選ばれたプランで導入する

`timeout_ms` を 180000 にして実行する。

```bash
TD_WORKDIR="<WORKDIR>" [NPM_REGISTRY="<URL>"] bash setup-tdx.sh install <A|B|C|D>
```

- 導入に失敗した場合、既存の `runtime/` は自動で元に戻る
- C は SHA-256 が一致しない一式を展開しない。その場合はユーザーに一式の作り直しを依頼する
- 成功すると `tdx_setup.conf` にプラン・版・ミラー URL が記録される。これがお客様の設定になる

## Step 5: 検証する

```bash
TD_WORKDIR="<WORKDIR>" bash setup-tdx.sh verify
```

検証項目: TD の API / CDP / ワークフローの各ホストへの到達、tdx の版が記録どおりか、認証、見えるデータベース数（権限範囲）、ワークフロー API の参照可否。結果を `[OK]` / `[NG]` のまま要約して伝える。

- `VERIFY=PASS` なら完了。見えるデータベースが組織の全 DB に近い場合は、そのキーがポリシーで絞られていないことを1行伝え、専用ユーザーのキーへの差し替えを選択肢として添える。繰り返さない
- `VERIFY=FAIL` なら `[NG]` の項目に応じて `references/troubleshooting.md` を見る

## Step 6: 実行する

### プラン A〜C（tdx）

毎回このプレフィックスを付ける（`device_bash` は毎回新しいシェル）。

```bash
source "<WORKDIR>/setup-tdx.sh" >/dev/null
tdx --site "$TDX_SITE" <コマンド>
```

tdx の全コマンドを使ってよい。コマンドとクエリの流儀は `references/tdx-commands.md` を読む。

### プラン D（td-api.sh）

```bash
TD_WORKDIR="<WORKDIR>" "<WORKDIR>/td-api.sh" <コマンド>
```

使えるコマンドは `td-api.sh help`。書き込み系 SQL はユーザーの了承を得てから `TD_ALLOW_WRITE=1` を付ける。tdx でしかできない操作を頼まれたら、A〜C への切り替え（Step 3）を提案する。

### 共通

**キーの中身を表示しない。** `cat tdx_key.txt` や `echo $TDX_API_KEY` を実行しない。

---

## 権限の扱い

**実効的な権限境界は、キーが指す Treasure Data ユーザーの権限だけ。**

- **本番データを変更する操作の前に、必ずユーザーに確認を取る。** テーブルの削除・更新、セグメントやジャーニーの変更、Engage の配信、ワークフローの push / run / delete、スケジュールの変更が該当する
- `-y` / `--yes`、`TD_ALLOW_WRITE=1` を自分の判断で付けない。ユーザーが明示したときだけ
- 技術的な理由で実行しないもの:
  - `tdx auth login` / `auth logout` / `profile` — キーファイル方式の認証を壊す（`auth status` は可）
  - `tdx claude` / `codex` / `mcp` — 対話・常駐プロセスで返らなくなる
  - `tdx upgrade` — `tdx_setup.conf` の版とずれる。版を上げるときは `TDX_VERSION=<版>` を付けて Step 4 をやり直す（C は新しい一式を作る）
- 対話入力を求めるコマンド（引数なしの `wf run` など）は、引数を明示して実行する

---

## PC と繋がっていない場合

`device_bash` が無いセッションでも、クラウド側のシェルで同じ手順が動く。ただしキーファイルを読めないため、ユーザーに添付してもらう必要がある。添付されたファイルは `/mnt/user-data/uploads/` から読み、`TD_WORKDIR` にそのディレクトリを指定して使う。**中身を出力しない。** この経路を使ったら、セッション後にキーを無効化して作り直すよう伝える。

渋る場合は無理に勧めない。PC を繋ぐ方が安全だと伝える。
