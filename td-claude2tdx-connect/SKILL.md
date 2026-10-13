---
name: td-claude2tdx-connect
description: 'Use whenever the user wants to query, inspect, or operate Treasure Data from Claude — running SQL, listing databases or tables, checking schemas, CDP segments, journeys, Engage, workflows, jobs, or schedules. Also use immediately after this plugin is installed, and whenever Treasure Data access needs to be set up or is failing. Triggers on phrases like "TDのDBを教えて", "TDでクエリして", "テーブルの中身見せて", "セグメントを確認して", "ワークフロー流して", "TDに繋ぎたい", "TDのセットアップして", "td-claude2tdx-connect", "query Treasure Data", "list TD databases", "connect Claude to Treasure Data".'
---

# Treasure Data に接続して操作する

公式 CLI `tdx` を作業フォルダに導入し、同じフォルダのキーファイルで認証して Treasure Data を操作する。

接続を確立するときに、お客様と次の2つを決める。

1. **導入プラン** — tdx をどこから入れるか（お客様のネットワーク方針に合わせる）
2. **操作範囲** — tdx で何をしてよいか（例: SQL は実行できるが、ワークフローの更新はできない）

決めた内容は作業フォルダに記録され（`tdx_setup.conf` / `tdx_policy.conf`）、次回以降もそれに従う。操作範囲は `tdx-guard.sh` が強制する。`tdx` コマンドは必ずこのガードを通る。

**ブラウザで TD コンソールを開く、ユーザーに `td db:list` の結果を貼ってもらう、といった代替手段を提案しないこと。**

---

## 作業フォルダの構成

既定の名前は **`TreasureAI`**。

```
TreasureAI/
├── tdx_key.txt          1行目: API キー / 2行目: リージョン（任意、既定 us01）
├── tdx_setup.conf       導入プランの記録
├── tdx_policy.conf      操作範囲の記録
├── tdx_audit.log        ガードの判定ログ（許可・拒否した操作）
├── setup-tdx.sh         診断・導入・操作範囲・検証（プラグイン同梱のものを置く）
├── tdx-guard.sh         操作範囲のガード（同上）
├── td-api.sh            プラン D 用（同上）
├── tdx-bundle-*.tgz     プラン C 用の一式と .sha256
└── runtime/             tdx の導入先。runtime/bin/tdx はガード経由
```

---

## このスキルが呼ばれたら

**まず Step 1 を実行する。** 「セットアップしますか？」と聞かない。インストール直後に呼ばれた場合も同じ。

## Step 1: 状態を確認する

`device_bash` で1回実行する。

```bash
echo "--- connected folders ---"; ls "$HOME/mnt/" 2>/dev/null
echo "--- key file ---"; find "$HOME/mnt" -maxdepth 4 -name 'tdx_key.txt' -size +0 2>/dev/null
echo "--- setup ---";  find "$HOME/mnt" -maxdepth 4 \( -name 'tdx_setup.conf' -o -name 'tdx_policy.conf' \) -print -exec grep -v '^#' {} \; 2>/dev/null
```

| 結果 | 次 |
|---|---|
| キーが無い / 接続フォルダが無い | Step 2 |
| キーあり・`tdx_setup.conf` なし | Step 3 |
| `tdx_setup.conf` あり・`tdx_policy.conf` なし | Step 4 |
| 両方あり | Step 6（検証）。合格なら Step 7。不合格なら原因に応じて該当 Step へ |

以降、キーファイルのあるディレクトリを `<WORKDIR>` と呼ぶ。

## Step 2: 作業フォルダを決めてキーを置いてもらう

**フォルダをユーザーに確認してから作る。勝手に決めない。** 既定は `TreasureAI`。接続フォルダがあればその中にサブフォルダを作ることを勧める。

> 接続されている `<フォルダ名>` の中に `TreasureAI` というフォルダを作って、そこに API キーと tdx をまとめます。この名前で進めてよいですか？

承諾を得たら作成する。

```bash
mkdir -p "$HOME/mnt/<接続フォルダ>/TreasureAI"
: > "$HOME/mnt/<接続フォルダ>/TreasureAI/tdx_key.txt"
chmod 600 "$HOME/mnt/<接続フォルダ>/TreasureAI/tdx_key.txt"
```

**Finder 上のパスで案内する**（`~/mnt/...` はユーザーには見えない）。

> `<フォルダ名>` → `TreasureAI` → `tdx_key.txt` を開いて、1行目に Treasure Data の API キーを貼って保存してください。リージョンが `us01` 以外なら、2行目にリージョン名（`ap01` など）を書いてください。

接続フォルダが無ければ、Claude デスクトップアプリの「フォルダを追加」で接続してもらう。

**守ること:**

- **隠しファイル名（`.tdx_key` など）を提案しない。** Finder に表示されない
- キーをチャットに貼らせない。貼られてしまったら、そのキーを無効化して作り直すよう伝える
- 作業フォルダが git リポジトリの中なら、`.gitignore` に `tdx_key.txt`・`tdx_*.conf`・`tdx_audit.log`・`runtime/`・`tdx-bundle-*` を追加する

## Step 3: 環境を診断して導入プランを決める

このスキルのディレクトリにある `setup-tdx.sh`・`tdx-guard.sh`・`td-api.sh` を `<WORKDIR>` に置く（クラウド側で outputs にコピーし、`device_commit_files` で書き込む）。**中身は改変しない。**

```bash
cd "<WORKDIR>" && chmod +x setup-tdx.sh tdx-guard.sh td-api.sh
TD_WORKDIR="<WORKDIR>" bash setup-tdx.sh plan
# 社内ミラーがある場合
TD_WORKDIR="<WORKDIR>" NPM_REGISTRY="<URL>" bash setup-tdx.sh plan
```

| プラン | 導入元 | セッションに必要な通信許可 |
|---|---|---|
| A. npm 直接 | registry.npmjs.org（版固定） | TD ドメイン + `registry.npmjs.org` |
| B. 社内ミラー | お客様の npm ミラー（版固定） | TD ドメイン + ミラーのホスト |
| C. オフライン一式 | 管理端末で作った一式（SHA-256 照合） | TD ドメインのみ |
| D. curl のみ | tdx を入れず `td-api.sh` | TD ドメインのみ（機能限定） |

診断結果を表にしてユーザーに提示し、**`AskUserQuestion` でプランを選んでもらう**。`RECOMMENDED=` を先頭に置き「(推奨)」を付ける。利用不可のプランは、必要な設定を添えて示す。

| 利用不可の理由 | お客様側で必要な設定 |
|---|---|
| Treasure Data に到達できない | ネットワーク許可に `*.treasuredata.com` / `*.treasuredata.co.jp` |
| Node.js が無い・古い | セッション環境に Node.js 22.12 以上。用意できなければプラン D |
| registry.npmjs.org（A） | ネットワーク許可に `registry.npmjs.org` |
| ミラー（B） | ミラー URL と、そのホストのネットワーク許可。認証が要るなら `.npmrc` |
| 一式（C） | 管理端末で `scripts/build-tdx-bundle.sh` を実行し、一式を作業フォルダに置く |

**npm を許可できない環境で A を勧めない。** 選ばれたプランが今は利用不可なら、必要な設定を案内して待ち、`plan` を再実行して `○` を確認してから進む。

## Step 4: 操作範囲を決める

**お客様に確認してから決める。Claude が勝手に広げない。** まずプリセットを表で示す。

```bash
TD_WORKDIR="<WORKDIR>" bash setup-tdx.sh policy presets
```

| カテゴリ | 対象 |
|---|---|
| data | DB・テーブル参照、SQL（SELECT 系は read、INSERT / CTAS / DELETE などは write）、ジョブ |
| workflow | ワークフローの参照（read）、push / run / 削除 / スケジュール / シークレット（write） |
| cdp | 親セグメント、セグメント、アクティベーション、CAS |
| journey | ジャーニー |
| engage | Engage・配信（キャンペーンの起動・送信は write） |
| ai | LLM エージェント・チャット |
| admin | ユーザー・ポリシー（read まで） |

水準は `none`（不可）/ `read`（参照のみ）/ `write`（参照・更新）。

**`AskUserQuestion` で2問聞く。**

1. 「どの範囲で使いますか？」— 選択肢: `参照のみ（readonly）` / `分析: SQL 書き込み可・WF は参照のみ（analyst）` / `分析＋ワークフロー運用（wf-ops）` / `施策運用: セグメント・ジャーニー・Engage を更新（marketing）`。全権（full）や個別指定は「その他」で受ける。迷っている場合は readonly を推奨として先頭に置く
2. 「個別に変えたい項目はありますか？」（multiSelect）— 例: `ワークフローを不可にする` / `CDP を不可にする` / `Engage を不可にする` / `変更なし`

決まったら書き込む。

```bash
TD_WORKDIR="<WORKDIR>" bash setup-tdx.sh policy set <プリセット> [カテゴリ=水準 ...]
# 例: SQL は書き込みまで可、ワークフローは参照のみ、CDP は不可
TD_WORKDIR="<WORKDIR>" bash setup-tdx.sh policy set analyst cdp=none
```

出力される「操作範囲」の表と、**「Treasure Data 側で合わせる設定」をユーザーに伝える。** クライアント側の制限は誤操作防止で、最終的な境界は TD のポリシーであることを1行添える。

## Step 5: 導入する

`timeout_ms` を 180000 にして実行する。

```bash
TD_WORKDIR="<WORKDIR>" [NPM_REGISTRY="<URL>"] bash setup-tdx.sh install <A|B|C|D>
```

- プラン A〜C では、`runtime/bin/tdx` がガード（`tdx-guard.sh`）経由に差し替わる
- 失敗した場合、既存の `runtime/` は自動で元に戻る
- C は SHA-256 が一致しない一式を展開しない

## Step 6: 検証する

```bash
TD_WORKDIR="<WORKDIR>" bash setup-tdx.sh verify
```

検証項目: TD の各ホストへの到達、tdx の版、認証、見えるデータベース数、ワークフロー API、**ガードが組み込まれているか、各カテゴリの代表操作をガードが操作範囲どおりに許可・拒否するか。** 結果を `[OK]` / `[NG]` のまま要約して伝える。

- `VERIFY=PASS` なら完了。見えるデータベースが組織の全 DB に近い場合は、そのキーが TD 側で絞られていないことを1行伝える。繰り返さない
- `VERIFY=FAIL` なら `references/troubleshooting.md` を見る

## Step 7: 実行する

### プラン A〜C（tdx）

毎回このプレフィックスを付ける（`device_bash` は毎回新しいシェル）。

```bash
source "<WORKDIR>/setup-tdx.sh" >/dev/null
tdx --site "$TDX_SITE" <コマンド>
```

コマンドとクエリの流儀は `references/tdx-commands.md` を読む。

### プラン D（td-api.sh）

```bash
TD_WORKDIR="<WORKDIR>" "<WORKDIR>/td-api.sh" <コマンド>
```

td-api.sh も同じ `tdx_policy.conf` に従う（data / workflow / cdp）。tdx でしかできない操作を頼まれたら、A〜C への切り替え（Step 3）を提案する。

### 書き込み操作

操作範囲で `write` のカテゴリでも、書き込み操作は **都度ユーザーの了承を得てから** `TD_ALLOW_WRITE=1` を付けて実行する。

```bash
TD_ALLOW_WRITE=1 tdx --site "$TDX_SITE" wf push ./project
```

- 了承を得る前に、可能なら `--dry-run`（ガードは了承なしで通す）で影響を見せる。例: `wf push --dry-run`
- `TD_ALLOW_WRITE=1` や `-y` を自分の判断で付けない

### ガードに止められたら

`tdx-guard: 実行しませんでした — 操作範囲外: ...` と出たら、**その操作は今の操作範囲ではできない**とユーザーに伝える。

- **回避しない。** `node .../dist/bin.js` を直接叩く、`tdx_policy.conf` や `tdx-guard.sh` を書き換える、td-api.sh の `get` などで同じ操作を試す、といったことをしない
- 範囲を広げる必要があるなら、ユーザーがそれを明示的に求めた場合に限り、Step 4 の `policy set` をやり直す。変更前後の表を示す
- 「分類できないコマンド」で止められた場合も同じ。分類を変えたいときはユーザーに相談する

### 共通

- **キーの中身を表示しない。** `cat tdx_key.txt` や `echo $TDX_API_KEY` を実行しない
- 対話入力を求めるコマンド（引数なしの `wf run` など）は、引数を明示して実行する
- tdx が `Update available ... Run: tdx upgrade` と表示しても無視する。`upgrade` はガードが止める。版を上げるのはユーザーが求めたときに Step 5 で行う
- ユーザーから「何をしたか確認したい」と言われたら `tdx_audit.log` を見せる

---

## ガードが常に止める tdx コマンド

| コマンド | 理由 |
|---|---|
| `auth login` / `auth logout` / `profile` | キーファイル方式の認証を壊す（`auth status` は可） |
| `claude` / `codex` / `mcp` / `chats` / `work` | 対話・常駐プロセスで返らなくなる |
| `upgrade` | `tdx_setup.conf` の版とずれる。版を上げるときは `TDX_VERSION=<版>` を付けて Step 5 をやり直す |

---

## PC と繋がっていない場合

`device_bash` が無いセッションでも、クラウド側のシェルで同じ手順が動く。ただしキーファイルを読めないため、ユーザーに添付してもらう必要がある。添付されたファイルは `/mnt/user-data/uploads/` から読み、`TD_WORKDIR` にそのディレクトリを指定して使う。この場合 `tdx_policy.conf` もクラウド側に作り直す必要があるので、Step 4 を行う。**キーの中身を出力しない。** この経路を使ったら、セッション後にキーを無効化して作り直すよう伝える。

渋る場合は無理に勧めない。PC を繋ぐ方が安全だと伝える。
