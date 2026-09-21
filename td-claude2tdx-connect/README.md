# td-claude2tdx-connect

Treasure AI の公式 CLI **[tdx](https://tdx.treasuredata.com/)** を使って、Claude から Treasure Data を操作するプラグイン。

クエリ、スキーマ確認、CDP セグメント、ジャーニー、Engage、ワークフロー、ジョブまで、tdx が扱えるものはひととおり操作できます。API キーは利用者の PC 上のファイルに置いたままで、会話履歴には残りません。

> **以前の `.mcpb` デスクトップ拡張版は廃止しました。** 拡張機能は Claude デスクトップアプリのチャット専用で、Cowork のセッションでは動かなかったためです。現在は tdx CLI をセッションに直接導入する方式に統一しています。

---

## インストール

```
/plugin marketplace add tsukaharakazuki/td_tas_skill_extension
```

`td-claude2tdx-connect` をインストールしたあと、

> TDに繋ぎたい

と話しかければ、Claude が状態を確認してセットアップを進めます。足りないものだけを聞かれます。

---

## 準備するもの

### 1. フォルダを接続する

Claude デスクトップアプリで作業フォルダを1つ接続します。

### 2. API キーを置く

接続したフォルダの直下に **`tdx_key.txt`** を作り、Treasure Data の API キーを1行で書きます。

```
1234/abcdef0123456789abcdef0123456789abcdef01
```

リージョンが `us01` 以外なら、2行目にリージョン名を書きます。

```
1234/abcdef0123456789abcdef0123456789abcdef01
ap01
```

指定できるのは `us01` / `ap01` / `eu01` / `ap02` です。`jp01` と書いた場合は `ap01` として扱われます（同じリージョンの別名）。

**キーをチャットに貼らないでください。** 会話履歴に残ります。リポジトリ内に置く場合は `.gitignore` に `tdx_key.txt` を追加してください。

### 3. ネットワークを許可する

Claude のセッションは既定で Treasure Data に到達できません。Claude のネットワークアクセス設定で、許可ドメインに次を追加してください。

```
*.treasuredata.co.jp
*.treasuredata.com
```

**これを忘れると、tdx のインストールだけ成功して認証で落ちます。** npm registry は既定で許可されているためです。Team / Enterprise では管理者設定になります。

---

## ⚠️ 権限について

**このプラグインには安全装置がありません。**

tdx を直接実行するため、参照も書き込みも同じように通ります。**実効的な権限境界は、API キーが指す Treasure Data ユーザーの権限だけ**です。

本番データを変更する操作の前には Claude が確認を取りますが、それを唯一の防波堤にしないでください。

### 先に Treasure Data 側を設定してください

1. Control Panel → **Users** で用途専用のユーザーを作成
2. Control Panel → **Policies** でポリシーを作成し、**対象データベースと操作範囲を実際の用途まで絞る**
3. そのポリシーをユーザーに割り当てる
4. そのユーザーの **My Settings → API Keys** から Master Key を取得

管理者アカウントのキーをそのまま使わないでください。参照しかしないなら、TD 側で readonly のポリシーを作ってください。

キーの権限が広いかどうかは `tdx databases` の件数で当たりがつきます。組織の全データベースが見えているなら、ポリシーで絞られていません。

### Claude が実行しないコマンド

| コマンド | 理由 |
|---|---|
| `auth` / `profile` / `profiles` | 認証情報を壊す |
| `mcp` | MCP サーバーの入れ子起動 |
| `upgrade` | バージョンが変わり再現性が落ちる |
| `claude` / `codex` | 対話型エージェントの起動。返らなくなる |

`user` / `policy` の**変更**は、明示的に頼んだときだけ実行します。

---

## 構成

| | |
|---|---|
| `SKILL.md` | セットアップ、コマンド実行、権限の扱い |
| `references/tdx-commands.md` | コマンド早見、クエリの流儀 |
| `references/troubleshooting.md` | 症状別の対処 |
| `setup-tdx.sh` | セットアップを手動で流したいとき用 |

---

## 手動セットアップ

Claude に任せず自分で流す場合:

```bash
source ./setup-tdx.sh
```

未インストールなら tdx を入れ、`tdx_key.txt` を読んで、認証確認まで行います。

| 環境変数 | 既定 | 用途 |
|---|---|---|
| `TDX_VERSION` | `2026.9.0` | 入れる tdx のバージョン |
| `TDX_SITE` | `us01` | リージョン |
| `TDX_KEY_FILE` | スクリプトと同階層 → リポジトリ直下の `tdx_key.txt` | キーの置き場所 |

---

## 既知の制限

- **セッションをまたぐと tdx は消えます。** Claude のセッション環境は使い捨てで、毎回再インストールが必要です（30秒ほど、自動で行われます）。`tdx_key.txt` は接続フォルダの中なので残ります
- **フォルダ接続は毎回必要です。** セッションごとに許可が要るため、完全にゼロ手作業にはできません
- 1コマンドの実行時間には上限があります。重いクエリは `job submit` → `job status` に分けてください

---

## ライセンス

Apache-2.0

## 不具合報告

https://github.com/tsukaharakazuki/td_tas_skill_extension/issues
