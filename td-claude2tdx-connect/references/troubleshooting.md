# 症状別の対処

## ネットワーク

### `403 CONNECT` / `connect_rejected` / curl が `000` を返す

Cowork のセッションは egress プロキシ経由でしか外に出られず、既定では Treasure Data に到達できない。

確認:

```bash
curl -s -o /dev/null -w '%{http_code}\n' --max-time 15 https://api.treasuredata.com/v3/system/server_status
```

`200` 以外なら、ユーザーに Claude のネットワークアクセス設定で許可ドメインに次を追加してもらう。

```
*.treasuredata.co.jp
*.treasuredata.com
```

Team / Enterprise では管理者設定。個人アカウントでは設定画面のネットワークアクセス項目。

**npm registry は既定で許可されている。** そのため tdx のインストールだけは成功し、「入ったのに認証で落ちる」という形で表面化する。インストールが通ったことを根拠にネットワークは大丈夫だと判断しない。

## 認証

### `No credential found`

環境変数名が違う。`TDX_API_KEY` を使う。`TD_API_KEY` は読まれない。

正しく読めていれば `Read credential from TDX_API_KEY env var` と表示される。

### `Authentication failed` / `Failed to Login`

読み込みはできているが弾かれている。順に疑う。

1. **リージョン違い。** `us01` のキーで `ap01` を叩けば落ちる。`tdx_key.txt` の2行目にリージョンを書いてもらうか、ユーザーに確認する
2. **キーの前後に余分な文字。** 改行や引用符が混じっていないか。`${#TDX_API_KEY}` で長さを確認する（中身は表示しない）
3. **キーが失効している。** Control Panel で再発行してもらう

### リージョンの表記

`jp01` を指定すると `site: ap01` と表示される。同じリージョンの別名で、エラーではない。`tdx --help` の一覧には `us01` / `ap01` / `eu01` / `ap02` が載っている。

## インストール

### `tdx: command not found`

`<WORKDIR>/runtime/bin` が PATH に入っていない。`device_bash` は毎回新しいシェルなので、コマンドごとに次を付ける。

```bash
export PATH="<WORKDIR>/runtime/bin:$PATH"
```

runtime は接続フォルダの中にあるので消えていない。まず PATH を疑う。

### `npm error code: 'EACCES'`

`--prefix` を付け忘れて `/usr` に入れようとしている。作業フォルダを指定する。

```bash
npm i -g --prefix "<WORKDIR>/runtime" @treasuredata/tdx
```

### runtime が見つからない

作業フォルダを含むフォルダが接続されていない可能性がある。接続フォルダ一覧を確認する。

```bash
ls "$HOME/mnt/"
find "$HOME/mnt" -maxdepth 5 -path '*/runtime/bin/tdx' 2>/dev/null
```

作業フォルダごと移動・改名された場合は、キーファイルの場所から辿り直す。

### 別のマシンで使えない

`runtime/` は導入したマシンの Node 環境に依存する。同期フォルダ経由で別マシンに持っていった場合は、そのマシンで入れ直す。

## 実行

### コマンドが返ってこない

`device_bash` は既定120秒、最大180秒。重いクエリは `job submit` に回し、`job status` でポーリングする。

`tdx claude` / `tdx codex` は対話型エージェントを起動するため絶対に実行しない。返らなくなる。

### `tdx upgrade` を実行してよいか

しない。バージョンが変わると挙動が変わり、再現性が落ちる。バージョンを上げたい場合はユーザーに相談してから `npm i -g @treasuredata/tdx@<version>` を使う。

## ファイル

### ユーザーがキーファイルを見つけられない

Finder は `.` で始まるファイルを表示しない。`tdx_key.txt` のような可視名を使う。既に隠しファイルで作ってしまった場合、Finder 上で **⌘ + Shift + .** でも表示を切り替えられる。

### キーをリポジトリに置く場合

`.gitignore` に `tdx_key.txt` と `runtime/` を追加し、`git check-ignore -v tdx_key.txt` で除外を確認してからコミットする。公開リポジトリなら特に確認を省かない。

### 作業フォルダをどこに作るか

既定は `TreasureAI`。Claude Cowork 用のフォルダを既に接続しているなら、その中にサブフォルダとして作る。既存フォルダの直下にキーファイルや `runtime/` を置かない。

iCloud や Dropbox の同期対象は避ける。`runtime/` は約 60MB あり、同期の無駄になる。
