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

### `npm error code: 'EACCES'`

npm prefix が `/usr` を指しており、書き込み権限がない。

```bash
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
```

### `tdx: command not found`（インストール直後）

`$HOME/.npm-global/bin` が PATH に入っていない。`device_bash` は毎回新しいシェルなので、コマンドごとに `export PATH=...` を付ける。

### セッションを開き直したら tdx が消えた

Cowork VM のホームディレクトリは使い捨て。毎セッション再インストールが必要で、これは正常な挙動。障害として報告せず、黙ってセットアップし直す。接続フォルダの中にある `tdx_key.txt` は残っている。

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

`.gitignore` に `tdx_key.txt` を追加し、`git check-ignore -v tdx_key.txt` で除外を確認してからコミットする。公開リポジトリなら特に確認を省かない。
