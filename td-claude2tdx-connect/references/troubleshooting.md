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

`registry.npmjs.org` が必要なのはプラン A だけ。お客様が許可できない場合に許可を求めない。

### `registry.npmjs.org` を許可できないと言われた

許可しなくてよい。`setup-tdx.sh plan` を再実行し、次から選んでもらう。

- 社内ミラーがある → プラン B（`NPM_REGISTRY=<URL>` を付けて plan）
- ミラーが無い → プラン C（管理端末で `scripts/build-tdx-bundle.sh` を実行し、一式を作業フォルダに置く）
- Node.js も用意できない → プラン D（`td-api.sh`、機能限定）

### 社内ミラーで `取得できない`（プラン B）

順に疑う。

1. ミラーのホストがネットワーク許可に入っていない
2. 認証が要るミラーで `.npmrc` の設定が無い（ミラー管理者に確認）
3. ミラーに指定の版が同期されていない（`TDX_VERSION` を同期済みの版にするか、ミラー側で取り込んでもらう）

## 検証（setup-tdx.sh verify）の [NG]

| 項目 | 対処 |
|---|---|
| 到達できない: api-cdp / api-workflow | 許可が `api.` だけになっている。`*.treasuredata.com` / `*.treasuredata.co.jp` か各ホストを追加 |
| 版が期待と違う | `tdx upgrade` などで版がずれた。Step 4 で入れ直す |
| 認証: 失敗 | 下の「認証」を参照 |
| データベースが1件も見えない | キーのユーザーにポリシーが割り当てられていないか、リージョン違い |
| ワークフロー API: 参照できない | ポリシーでワークフロー権限が無い。必要ならユーザーの権限を見直してもらう |

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
source "<WORKDIR>/setup-tdx.sh" >/dev/null
```

runtime は接続フォルダの中にあるので消えていない。まず PATH を疑う。

### `SHA-256 が一致しません`

一式が転送中に壊れたか、改変されている。**展開しない。** 管理端末で `build-tdx-bundle.sh` を実行し直し、`.tgz` と `.sha256` を両方置き直してもらう。

### `署名検証に失敗しました`（build-tdx-bundle.sh）

管理端末から `registry.npmjs.org` と `tuf-repo-cdn.sigstore.dev` に到達できる必要がある。社内ミラーで署名検証が通らない場合は、ミラーの管理者に署名の扱いを確認する。`SKIP_SIGNATURE_CHECK=1` で省略できるが、審査に出す一式には使わない。

### td-api.sh（プラン D）: `参照系以外の SQL は既定で止めています`

書き込み系の SQL と判定された。本当に実行する必要があるならユーザーに確認を取り、了承を得てから `TD_ALLOW_WRITE=1` を付けて再実行する。文字列リテラルの中の単語（`'DELETE'` など）で誤判定されることがあるが、その場合も同じ手順。

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

しない。npm に繋ぎにいくうえ、バージョンが変わると再現性が落ちる。バージョンを上げたい場合は、管理端末で新しいバージョンの一式を作ってもらう。

## ファイル

### ユーザーがキーファイルを見つけられない

Finder は `.` で始まるファイルを表示しない。`tdx_key.txt` のような可視名を使う。既に隠しファイルで作ってしまった場合、Finder 上で **⌘ + Shift + .** でも表示を切り替えられる。

### キーをリポジトリに置く場合

`.gitignore` に `tdx_key.txt` と `runtime/` を追加し、`git check-ignore -v tdx_key.txt` で除外を確認してからコミットする。公開リポジトリなら特に確認を省かない。

### 作業フォルダをどこに作るか

既定は `TreasureAI`。Claude Cowork 用のフォルダを既に接続しているなら、その中にサブフォルダとして作る。既存フォルダの直下にキーファイルや `runtime/` を置かない。

iCloud や Dropbox の同期対象は避ける。`runtime/` は約 60MB あり、同期の無駄になる。
