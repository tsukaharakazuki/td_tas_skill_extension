# td-claude2tdx-connect

Claude から Treasure Data を操作するプラグイン。

クエリ、スキーマ確認、CDP セグメント、ワークフローの確認などを会話から実行できます。API キーは利用者の PC 上のファイルに置いたままで、会話履歴には残りません。

**npm（`registry.npmjs.org`）への通信許可は不要です。** Claude のセッションが通信するのは Treasure Data のドメインだけです。

> **以前の `.mcpb` デスクトップ拡張版は廃止しました。** 拡張機能は Claude デスクトップアプリのチャット専用で、Cowork のセッションでは動かなかったためです。
>
> **v1.10.0 から、セッション内で npm から tdx をインストールする方式をやめました。** 詳しくは「[セキュリティ審査向けの情報](#セキュリティ審査向けの情報)」を参照してください。

---

## 接続方式

| 方式 | 中身 | セッションの通信先 | 外部ライブラリ |
|---|---|---|---|
| **A. td-api.sh（既定）** | 同梱の bash スクリプト（約250行）。curl で TD の REST API を呼ぶ | `*.treasuredata.com` / `*.treasuredata.co.jp` | なし（bash / curl。python3 があれば表示を整形） |
| **B. tdx 検証済み一式（任意）** | 公式 CLI [tdx](https://tdx.treasuredata.com/) を、管理端末で検証・固定したオフライン一式から展開 | 同上 | 約180パッケージ（lockfile で完全固定、SBOM 同梱） |

ほとんどの用途は **方式A** で足ります。ジャーニーや Engage など tdx でしか扱いにくい操作が要る場合だけ、方式B を追加してください。

### 方式A でできること

| | コマンド |
|---|---|
| 認証・疎通確認 | `td-api.sh status` |
| DB / テーブル / スキーマ | `databases` / `tables <db>` / `describe <db> <table>` |
| クエリ（Trino / Hive） | `query <db> "<SQL>"`（参照系のみ。書き込みは明示的な許可が必要） |
| ジョブ | `job-status <id>` / `job-result <id>` |
| CDP | `parent-segments` / `segments <parent_segment_id>` |
| ワークフロー | `wf-projects` / `wf-workflows <project_id>` / `wf-attempts` |
| その他の参照 API | `get <api\|cdp\|workflow> /<path>`（GET のみ） |

---

## インストール

```
/plugin marketplace add tsukaharakazuki/td_tas_skill_extension
```

`td-claude2tdx-connect` をインストールしたあと、

> TDに繋ぎたい

と話しかければ、Claude が作業フォルダの場所を相談し、接続まで進めます。

---

## 作業フォルダ

API キーと接続用スクリプトを1つのフォルダにまとめます。既定の名前は **`TreasureAI`**。

```
TreasureAI/
├── tdx_key.txt                  1行目: API キー / 2行目: リージョン（任意、既定 us01）
├── td-api.sh                    方式A（Claude が配置します）
├── tdx-bundle-<ver>.tgz         方式B を使う場合のみ
├── tdx-bundle-<ver>.tgz.sha256
└── runtime/                     方式B の展開先（約 60MB）
```

**Claude Cowork 用のフォルダを既に接続している場合は、その中に `TreasureAI` を作ることを勧めます。** Claude がフォルダ名を確認してから作成します。

### API キーの置き方

`tdx_key.txt` の1行目に API キーを書きます。

```
1234/abcdef0123456789abcdef0123456789abcdef01
```

リージョンが `us01` 以外なら、2行目にリージョン名を書きます。

```
1234/abcdef0123456789abcdef0123456789abcdef01
ap01
```

指定できるのは `us01` / `ap01` / `eu01` / `ap02` です。`jp01` と書いた場合は `ap01` として扱われます。

**キーをチャットに貼らないでください。** 会話履歴に残ります。作業フォルダが git リポジトリの中にある場合は、`.gitignore` に `tdx_key.txt`・`runtime/`・`tdx-bundle-*` を追加してください。

### ネットワークを許可する

Claude のネットワークアクセス設定で、許可ドメインに次を追加してください。**これ以外は不要です。**

```
*.treasuredata.co.jp
*.treasuredata.com
```

リージョンを限定したい場合は、使うホストだけを許可しても動きます。

| リージョン | ホスト |
|---|---|
| us01 | `api.treasuredata.com` / `api-cdp.treasuredata.com` / `api-workflow.treasuredata.com` |
| ap01 | `api.treasuredata.co.jp` / `api-cdp.treasuredata.co.jp` / `api-workflow.treasuredata.co.jp` |
| eu01 | `api.eu01.treasuredata.com` / `api-cdp.eu01.treasuredata.com` / `api-workflow.eu01.treasuredata.com` |
| ap02 | `api.ap02.treasuredata.com` / `api-cdp.ap02.treasuredata.com` / `api-workflow.ap02.treasuredata.com` |

Team / Enterprise では管理者設定になります。

---

## 方式B: tdx の検証済み一式を作る（任意）

セッションから npm に繋がずに tdx を使うための手順です。**npm に到達できる管理された端末**（または社内の npm ミラーを使える端末）で1回だけ実行します。Node.js 22.12 以上が必要です。

```bash
./scripts/build-tdx-bundle.sh 2026.9.0 ~/TreasureAI
# 社内ミラーを使う場合
NPM_REGISTRY=https://npm.example.co.jp/ ./scripts/build-tdx-bundle.sh 2026.9.0 ~/TreasureAI
```

スクリプトが行うこと:

1. `@treasuredata/tdx` をバージョン完全固定で取得し、依存も `package-lock.json` で固定する
2. install スクリプトを実行しない（`--ignore-scripts`）
3. OS 依存のネイティブモジュール（キーチェーン連携。API キーは環境変数で渡すため不要）を除外し、純 JS の一式にする
4. `npm audit signatures` で全パッケージのレジストリ署名を検証する。**失敗したら一式を作らない**
5. 既知の脆弱性レポート（`npm audit`）と SBOM（CycloneDX）を出力する
6. `tdx-bundle-<ver>.tgz` と SHA-256 を出力する

出力物:

| ファイル | 用途 |
|---|---|
| `tdx-bundle-<ver>.tgz` / `.sha256` | 作業フォルダに置く。展開前に SHA-256 を照合する |
| `tdx-bundle-<ver>.package-lock.json` | 含まれる全パッケージとハッシュ。審査用 |
| `tdx-bundle-<ver>.sbom.cdx.json` | SBOM（CycloneDX）。審査用 |
| `tdx-bundle-<ver>.audit.txt` / `.signatures.txt` | 脆弱性レポートと署名検証結果。審査用 |

一式を作業フォルダに置けば、Claude が SHA-256 を照合して `runtime/` に展開します。**照合に失敗した一式は展開しません。**

---

## セキュリティ審査向けの情報

### npm を許可しない理由

`registry.npmjs.org` を許可すると、tdx だけでなく **npm 上の任意のパッケージ**をセッションが取得できるようになります。また、以前の方式は依存パッケージのバージョンを固定しておらず、インストールのたびに推移的依存（約180パッケージ）が最新版に解決されていました。依存パッケージが乗っ取られた場合、その時点でインストールした環境に影響が及びます。

v1.10.0 からは次のとおりです。

| | 方式A（td-api.sh） | 方式B（tdx 一式） |
|---|---|---|
| セッション内のパッケージ取得 | なし | なし |
| セッションの通信先 | TD のドメインのみ | TD のドメインのみ |
| 実行されるコード | 本リポジトリの bash スクリプト1本（全文レビュー可） | 管理端末で署名検証・固定した一式（lockfile / SBOM で内容を確認可） |
| 改ざん検知 | git の履歴 | 展開前に SHA-256 照合 |

### td-api.sh の実装上の配慮

- API キーをコマンドライン引数に載せない（`ps` で見えない）。curl にはプロセス置換経由で渡す
- 通信は HTTPS（TLS 1.2 以上）のみ。宛先はリージョンごとの TD ホストに固定し、それ以外には送らない
- `query` は既定で参照系 SQL（SELECT / WITH / SHOW / DESCRIBE / EXPLAIN）のみ通す。書き込み系はユーザーの了承を得たうえで `TD_ALLOW_WRITE=1` を付けたときだけ
- `get` は GET メソッドのみ
- 一時ファイルは権限 700 の一時ディレクトリに作り、終了時に削除する

### 方式B の補足

- tdx は起動時に `registry.npmjs.org` へ新バージョンの有無を問い合わせることがあります（タイムアウト 2 秒）。許可していない環境では失敗して無視されるだけで、動作に影響はありません
- `tdx upgrade` は npm から更新を取得するため、Claude は実行しません

---

## ⚠️ 権限について

**実効的な権限境界は、API キーが指す Treasure Data ユーザーの権限だけ**です。td-api.sh の参照系ガードは誤操作防止であり、セキュリティ境界ではありません。

本番データを変更する操作の前には Claude が確認を取りますが、それを唯一の防波堤にしないでください。

### 先に Treasure Data 側を設定してください

1. Control Panel → **Users** で用途専用のユーザーを作成
2. Control Panel → **Policies** でポリシーを作成し、**対象データベースと操作範囲を実際の用途まで絞る**
3. そのポリシーをユーザーに割り当てる
4. そのユーザーの **My Settings → API Keys** から API キーを取得

管理者アカウントのキーをそのまま使わないでください。参照しかしないなら、TD 側で readonly のポリシーを作ってください。

キーの権限が広いかどうかは `td-api.sh status` の「見えるデータベース」の件数で当たりがつきます。

### Claude が実行しないコマンド（方式B）

| コマンド | 理由 |
|---|---|
| `auth login` / `auth logout` / `profile` / `profiles` | 認証情報を壊す。`auth status` は参照のみなので実行します |
| `mcp` | MCP サーバーの入れ子起動 |
| `upgrade` | npm に繋ぎにいく。バージョンが変わり再現性も落ちる |
| `claude` / `codex` | 対話型エージェントの起動。返らなくなる |

---

## 構成

| | |
|---|---|
| `SKILL.md` | 作業フォルダの決定、セットアップ、コマンド実行、権限の扱い |
| `td-api.sh` | 方式A。curl だけの TD API クライアント |
| `setup-tdx.sh` | 方式B のセットアップを手動で流したいとき用 |
| `scripts/build-tdx-bundle.sh` | 方式B の検証済み一式を作る（管理端末で実行） |
| `references/tdx-commands.md` | tdx のコマンド早見、クエリの流儀 |
| `references/troubleshooting.md` | 症状別の対処 |

---

## 手動セットアップ

```bash
# 方式A
cp td-api.sh ~/TreasureAI/ && TD_WORKDIR=~/TreasureAI ~/TreasureAI/td-api.sh status

# 方式B（一式を ~/TreasureAI に置いたうえで）
TD_WORKDIR=~/TreasureAI source ./setup-tdx.sh
```

`setup-tdx.sh` は npm に繋ぎません。一式が無い場合は何もインストールせず、方式A を案内して終わります。社内 npm ミラーなど許可された経路から入れる場合に限り、`TDX_ALLOW_NPM=1`（必要なら `NPM_REGISTRY=<URL>`）を明示してください。その場合もバージョン完全固定・install スクリプト無効で入れます。

| 環境変数 | 既定 | 用途 |
|---|---|---|
| `TD_WORKDIR` | 自動検出 | 作業フォルダ |
| `TDX_SITE` | キーファイル2行目 / `us01` | リージョン |
| `TD_MAX_ROWS` | `200` | td-api.sh の表示行数 |
| `TD_ALLOW_WRITE` | 未設定 | td-api.sh で書き込み系 SQL を許可 |
| `TDX_VERSION` | `2026.9.0` | 方式B の tdx バージョン |
| `TDX_ALLOW_NPM` | 未設定 | 方式B で npm からの取得を許可（非推奨） |

---

## 既知の制限

- **フォルダ接続は毎回必要です。** Claude のセッションはタスクごとに許可が要ります
- 方式A は参照系が中心です。ジャーニーの編集や Engage の配信などは方式B か TD コンソールを使ってください
- 1コマンドの実行時間には上限があります。重いクエリは `query` が返すジョブ ID で `job-status` → `job-result` に分けてください
- 作業フォルダが iCloud や Dropbox の同期対象にあると、方式B の `runtime/`（約 60MB）が同期されます

---

## ライセンス

Apache-2.0

## 不具合報告

https://github.com/tsukaharakazuki/td_tas_skill_extension/issues
