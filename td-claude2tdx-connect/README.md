# td-claude2tdx-connect

Treasure AI の公式 CLI **[tdx](https://tdx.treasuredata.com/)** を使って、Claude から Treasure Data を操作するプラグイン。

クエリ、スキーマ確認、CDP セグメント、ジャーニー、Engage、ワークフローの push / run まで、tdx が扱えるものはひととおり操作できます。API キーは利用者の PC 上のファイルに置いたままで、会話履歴には残りません。

**tdx の導入方法は、お客様のネットワーク方針に合わせて選べます。** Claude が環境を診断して導入プランを提示し、選んだプランで導入・検証します。`registry.npmjs.org` を許可できない環境でも使えます。

---

## インストール

```
/plugin marketplace add tsukaharakazuki/td_tas_skill_extension
```

`td-claude2tdx-connect` をインストールしたあと、

> TDに繋ぎたい

と話しかけると、Claude が次の順に進めます。

1. 作業フォルダの場所を相談し、API キーを置いてもらう
2. **環境を診断し、導入プランを提示する**（お客様が選ぶ）
3. 選ばれたプランで tdx を導入する
4. **導入結果を検証する**（版・通信・認証・権限範囲）

---

## 導入プラン

| プラン | 導入元 | セッションに必要な通信許可 | 向いている環境 |
|---|---|---|---|
| **A. npm 直接** | registry.npmjs.org（版固定） | TD ドメイン + `registry.npmjs.org` | npm の許可に問題がない |
| **B. 社内ミラー** | お客様の npm ミラー（版固定） | TD ドメイン + ミラーのホスト | Artifactory / Nexus などの社内ミラーがある |
| **C. オフライン一式** | 管理端末で作った一式を SHA-256 照合して展開 | **TD ドメインのみ** | npm を許可できない |
| **D. curl のみ** | tdx を入れず、同梱の `td-api.sh` を使う | **TD ドメインのみ** | Node.js を用意できない（機能限定） |

A〜C は Node.js 22.12 以上が必要です。どのプランでも、tdx は版を完全固定し、install スクリプトを実行せずに入れます。

### 診断の例

```
== 環境の診断（作業フォルダ: .../TreasureAI / リージョン: ap01 / tdx 2026.9.0）
[OK] Treasure Data に到達できる（api.treasuredata.co.jp）
[OK] Node.js v22.22.0（22.12 以上）
[--] 導入済みの tdx: なし
[--] registry.npmjs.org: 到達できない、または npm が無い
[--] 社内ミラー: 未指定（NPM_REGISTRY）
[OK] オフライン一式: tdx-bundle-2026.9.0.tgz（SHA-256 一致）

== 選べるプラン
  A npm 直接       × registry.npmjs.org の許可が必要
  B 社内ミラー     × NPM_REGISTRY に取得可能なミラーが必要
  C オフライン一式 ○ 利用可
  D curl のみ      ○ 利用可（tdx の全機能は使えない。参照・SQL・WF 参照中心）

== 推奨: プラン C
```

### 検証の例

```
== 検証（プラン C / リージョン ap01）
[OK] 到達: api.treasuredata.co.jp
[OK] 到達: api-cdp.treasuredata.co.jp
[OK] 到達: api-workflow.treasuredata.co.jp
[OK] 版: tdx 2026.9.0
[OK] 認証: 成功
[OK] 見えるデータベース: 12 件（多すぎる場合はポリシーで絞る）
[OK] ワークフロー API: 参照可

検証結果: 合格
```

選んだプランは作業フォルダの `tdx_setup.conf` に記録され、次回以降はそれに従います。

---

## 作業フォルダ

既定の名前は **`TreasureAI`**。

```
TreasureAI/
├── tdx_key.txt          1行目: API キー / 2行目: リージョン（任意、既定 us01）
├── tdx_setup.conf       選んだプランの記録
├── setup-tdx.sh         診断・導入・検証（Claude が配置）
├── td-api.sh            プラン D 用（Claude が配置）
├── tdx-bundle-*.tgz     プラン C 用の一式と .sha256
└── runtime/             tdx 本体（約 60MB）
```

**Claude Cowork 用のフォルダを既に接続している場合は、その中に `TreasureAI` を作ることを勧めます。** Claude がフォルダ名を確認してから作成します。

### API キーの置き方

`tdx_key.txt` の1行目に API キーを書きます。リージョンが `us01` 以外なら、2行目にリージョン名を書きます。

```
1234/abcdef0123456789abcdef0123456789abcdef01
ap01
```

指定できるのは `us01` / `ap01` / `eu01` / `ap02` です（`jp01` は `ap01` の別名）。

**キーをチャットに貼らないでください。** 作業フォルダが git リポジトリの中にある場合は、`.gitignore` に `tdx_key.txt`・`tdx_setup.conf`・`runtime/`・`tdx-bundle-*` を追加してください。

### ネットワークを許可する

Claude のネットワークアクセス設定で、許可ドメインに次を追加してください。全プランで必要です。

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

プラン A は `registry.npmjs.org`、プラン B はミラーのホストを追加で許可します。Team / Enterprise では管理者設定になります。

---

## プラン C: オフライン一式を作る

npm に到達できる管理された端末（または社内ミラーを使える端末）で1回だけ実行します。Node.js 22.12 以上が必要です。

```bash
./scripts/build-tdx-bundle.sh 2026.9.0 ~/TreasureAI
# 社内ミラーを使う場合
NPM_REGISTRY=https://npm.example.co.jp/ ./scripts/build-tdx-bundle.sh 2026.9.0 ~/TreasureAI
```

スクリプトが行うこと:

1. `@treasuredata/tdx` を版完全固定で取得し、依存も `package-lock.json` で固定する
2. install スクリプトを実行しない
3. OS 依存のネイティブモジュール（キーチェーン連携。API キーは環境変数で渡すため不要）を除外し、Mac で作っても Linux のセッションで動く一式にする
4. `npm audit signatures` で全パッケージのレジストリ署名を検証する。失敗したら一式を作らない
5. 脆弱性レポートと SBOM（CycloneDX）を出力する
6. `tdx-bundle-<ver>.tgz`（約 8MB）と SHA-256 を出力する

| 出力ファイル | 用途 |
|---|---|
| `tdx-bundle-<ver>.tgz` / `.sha256` | 作業フォルダに置く |
| `tdx-bundle-<ver>.package-lock.json` | 含まれる全パッケージとハッシュ |
| `tdx-bundle-<ver>.sbom.cdx.json` | SBOM |
| `tdx-bundle-<ver>.audit.txt` / `.signatures.txt` | 脆弱性レポート / 署名検証結果 |

---

## セキュリティ審査向けの情報

- どのプランでも、tdx は**版を完全固定**し、**install スクリプトを無効**にして導入します
- プラン C / D では、セッションは **Treasure Data のドメインにしか通信しません**
- プラン C の一式は展開前に **SHA-256 を照合**し、一致しなければ展開しません。一式の作成時には全パッケージの**レジストリ署名を検証**し、**lockfile・SBOM・脆弱性レポート**を出力します
- プラン D の `td-api.sh` は bash スクリプト1本（約250行）で、全文をレビューできます。API キーをコマンドライン引数に載せず、HTTPS で TD のホストにだけ送ります
- tdx は起動時に `registry.npmjs.org` へ新しい版の有無を問い合わせることがあります（タイムアウト 2 秒）。許可していない環境では失敗して無視されるだけで、動作に影響はありません

---

## ⚠️ 権限について

**実効的な権限境界は、API キーが指す Treasure Data ユーザーの権限だけ**です。本番データを変更する操作（テーブルの削除・更新、セグメント・ジャーニーの変更、Engage の配信、ワークフローの push / run / delete、スケジュールの変更）の前には Claude が確認を取りますが、それを唯一の防波堤にしないでください。

### 先に Treasure Data 側を設定してください

1. Control Panel → **Users** で用途専用のユーザーを作成
2. Control Panel → **Policies** でポリシーを作成し、**対象データベースと操作範囲を実際の用途まで絞る**
3. そのポリシーをユーザーに割り当てる
4. そのユーザーの **My Settings → API Keys** から API キーを取得

キーの権限が広いかどうかは、検証の「見えるデータベース」の件数で当たりがつきます。

### Claude が実行しない tdx コマンド

| コマンド | 理由 |
|---|---|
| `auth login` / `auth logout` / `profile` | キーファイル方式の認証を壊す。`auth status` は実行します |
| `claude` / `codex` / `mcp` | 対話・常駐プロセスで返らなくなる |
| `upgrade` | `tdx_setup.conf` の版とずれる。版を上げるときはプランに沿って入れ直す |

---

## 手動で流す場合

```bash
cp setup-tdx.sh td-api.sh ~/TreasureAI/
cd ~/TreasureAI
bash setup-tdx.sh plan                          # 診断（何も変更しない）
bash setup-tdx.sh install C                     # 導入（A / B / C / D）
bash setup-tdx.sh verify                        # 検証
source setup-tdx.sh && tdx --site "$TDX_SITE" databases
```

| 環境変数 | 既定 | 用途 |
|---|---|---|
| `TD_WORKDIR` | 自動検出 | 作業フォルダ |
| `TDX_VERSION` | `tdx_setup.conf` / `2026.9.0` | 導入する tdx の版 |
| `NPM_REGISTRY` | `tdx_setup.conf` / 未設定 | プラン B のミラー URL |
| `TDX_SITE` | キーファイル2行目 / `us01` | リージョン |

版を上げるときは `TDX_VERSION=<版> bash setup-tdx.sh install <プラン>` を実行します（プラン C は新しい版の一式を作って置き換える）。失敗した場合は以前の `runtime/` に自動で戻ります。

---

## 構成

| | |
|---|---|
| `SKILL.md` | 作業フォルダの決定、診断とプラン提示、導入、検証、コマンド実行、権限の扱い |
| `setup-tdx.sh` | `plan` / `install` / `verify`、`source` で環境読み込み |
| `td-api.sh` | プラン D の curl クライアント |
| `scripts/build-tdx-bundle.sh` | プラン C の一式を作る（管理端末で実行） |
| `references/tdx-commands.md` | tdx のコマンド早見、クエリの流儀 |
| `references/troubleshooting.md` | 症状別の対処 |

---

## 既知の制限

- **フォルダ接続は毎回必要です。** Claude のセッションはタスクごとに許可が要ります
- プラン D は参照・SQL・ワークフロー参照が中心です。ジャーニーや Engage、ワークフローの push / run は A〜C を使ってください
- 1コマンドの実行時間には上限があります。重いクエリは `job submit` → `job status` に分けてください
- 作業フォルダが iCloud や Dropbox の同期対象にあると、`runtime/`（約 60MB）が同期されます

---

## ライセンス

Apache-2.0

## 不具合報告

https://github.com/tsukaharakazuki/td_tas_skill_extension/issues
