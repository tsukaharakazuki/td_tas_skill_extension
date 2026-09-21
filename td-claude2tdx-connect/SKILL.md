---
name: td-claude2tdx-connect
description: 'Use whenever the user wants to query, inspect, or operate Treasure Data from Claude — running SQL, listing databases or tables, checking schemas, CDP segments, journeys, Engage, workflows, jobs, or schedules. Also use immediately after this plugin is installed, and whenever Treasure Data access needs to be set up or is failing. Triggers on phrases like "TDのDBを教えて", "TDでクエリして", "テーブルの中身見せて", "セグメントを確認して", "ワークフロー流して", "TDに繋ぎたい", "TDのセットアップして", "td-claude2tdx-connect", "query Treasure Data", "list TD databases", "connect Claude to Treasure Data".'
---

# Treasure Data に接続して操作する

`tdx` CLI をセッションに導入し、ユーザーの PC 上のキーファイルで認証して、Treasure Data を直接操作する。

**ブラウザで TD コンソールを開く、ユーザーに `td db:list` の結果を貼ってもらう、といった代替手段を提案しないこと。** 不要で、以下の手順で直接クエリできる。

---

## このスキルが呼ばれたら

**まず Step 1 を実行する。** 何をするか宣言してから確認するのではなく、確認してから状況を報告する。未設定なら Step 2 に進み、セットアップまで済ませる。「セットアップしますか？」と聞かない。キーが無いときだけユーザーに依頼が必要になる。

インストール直後に呼ばれた場合も同じ。Step 1 から始めて、足りないものだけをユーザーに頼む。

---

## Step 1: 状態を確認する

`device_bash` で1回実行する。

```bash
export PATH="$HOME/.npm-global/bin:$PATH"
echo "tdx: $(command -v tdx || echo none)"
echo "--- connected folders ---"; ls "$HOME/mnt/" 2>/dev/null
echo "--- key file ---"; find "$HOME/mnt" -maxdepth 3 -name 'tdx_key.txt' -size +0 2>/dev/null
```

| 状態 | 次 |
|---|---|
| tdx あり・キーあり | Step 3 |
| tdx なし・キーあり | Step 2 |
| キーが無い | Step 2 の「キーが無い場合」 |
| `device_bash` が使えない | 「PC と繋がっていない場合」へ |

## Step 2: セットアップする

`timeout_ms` を 180000 にして `device_bash` で実行する。インストールに30秒ほどかかる。

```bash
npm config get prefix | grep -q "$HOME/.npm-global" || npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
command -v tdx >/dev/null || npm i -g @treasuredata/tdx >/dev/null 2>&1
tdx --version
```

リポジトリを接続している場合は、同梱の `setup-tdx.sh` を `source` しても同じ結果になる。

**キーが無い場合。** ユーザーに次を依頼する — 「接続しているフォルダの直下に `tdx_key.txt` を作り、Treasure Data の API キーを1行だけ書いて保存してください。リージョンが `us01` 以外なら2行目にリージョン名を書いてください」。フォルダが未接続なら、先に Claude デスクトップアプリの「フォルダを追加」を頼む。

依頼時の注意:

- **隠しファイル名（`.tdx_key` など）を提案しない。** Finder に表示されず、ユーザーが開けない
- キーをチャットに貼らせない。会話履歴に残る。貼られてしまったら、そのキーを無効化して作り直すよう伝える
- リポジトリ内に置くなら `.gitignore` に `tdx_key.txt` を追加し、`git check-ignore -v tdx_key.txt` で除外を確認する

## Step 3: 実行する

毎回このプレフィックスを付ける。`<KEYDIR>` は Step 1 で見つけたディレクトリ。

```bash
export PATH="$HOME/.npm-global/bin:$PATH"
export TDX_API_KEY="$(sed -n '1p' <KEYDIR>/tdx_key.txt | tr -d '[:space:]')"
export TDX_SITE="$(sed -n '2p' <KEYDIR>/tdx_key.txt | tr -d '[:space:]')"; export TDX_SITE="${TDX_SITE:-us01}"
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

**`EACCES` (npm)** — npm prefix が `/usr`。Step 2 の `npm config set prefix` を実行する。

**セッションを開き直したら動かない** — Cowork のセッション環境は使い捨てで、毎回 tdx の再インストールが要る。正常な挙動なので障害として報告せず、黙って Step 1 からやり直す。

---

## PC と繋がっていない場合

`device_bash` が無いセッションでも、クラウド側のシェルで同じ手順が動く。ただしキーファイルを読めないため、ユーザーに添付してもらう必要がある。添付されたファイルは `/mnt/user-data/uploads/` から読み、環境変数に入れて使う。**中身を出力しない。** この経路を使ったら、セッション後にキーを無効化して作り直すよう伝える。

渋る場合は無理に勧めない。PC を繋ぐ方が安全だと伝える。
