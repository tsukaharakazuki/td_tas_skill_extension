---
name: engage-html-to-plaintext
description: 'Use when the user wants to generate a plaintext version of an EngageStudio email template from its HTML content. Triggers on EngageStudio email template URLs (`console-next.us01.treasuredata.com/app/es/.../em/...`), or phrases like "プレーンテキストを作成", "プレーンテキスト生成", "HTMLからテキスト版", "メールのテキスト版を作って".'
---

# EngageStudio HTML → プレーンテキスト生成

EngageStudio の Email Template について、HTMLメール本文の内容（画像内テキスト含む）を読み解き、配信用のプレーンテキスト本文を生成するスキル。生成後はユーザーに提示し、**同意を得たうえで** EngageStudio にPushする。勝手に上書きしない。

---

## 入力

ユーザーは EngageStudio の Email Template URL を提示する。形式：

```
https://console-next.us01.treasuredata.com/app/es/<WORKSPACE_ID>/em/<TEMPLATE_ID>
```

- `<WORKSPACE_ID>`: Engage workspace の UUID
- `<TEMPLATE_ID>`: Email Template の UUID（`em` = email template / message）

---

## 実行フロー

URLを受け取ったら以下を順に実行。各ステップ完了後にユーザーへ進捗を簡潔に通知する。

### Step 1: URL から ID を抽出

```python
import re
m = re.match(r'https?://console-next\.us01\.treasuredata\.com/app/es/([0-9a-f-]+)/em/([0-9a-f-]+)', url)
workspace_id, template_id = m.group(1), m.group(2)
```

### Step 2: 認証

```bash
tdx engage workspaces 2>&1 | head -3
```

「Authentication failed」が返ったら `mcp__tas__request_credential` で `td_api_production_aws` を取得し、

```bash
export TDX_ACCESS_TOKEN=$(curl -sf http://172.30.0.1:18080/credentials/td_api_production_aws)
export TDX_SITE=us01
```

を全コマンドの先頭に付与。

### Step 3: workspace 名を特定

`tdx engage workspaces` で workspace 一覧を取得し、各 workspace に対して下記を実行して `<WORKSPACE_ID>` と一致するものを探す：

```bash
tdx engage workspace show "<workspace_name>" --full --json 2>&1 | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
```

プロジェクトコンテキストに workspace 命名規則が記録されている場合は推測をかけて効率化する。

### Step 4: Template を一括 pull

特定した workspace から全テンプレートを YAML+HTML セットで pull：

```bash
mkdir -p /tmp/engage_html2txt && cd /tmp/engage_html2txt && \
  tdx engage template pull "<workspace_name>" --yes
```

pull先: `/tmp/engage_html2txt/templates/<workspace_name>/`

### Step 5: TEMPLATE_ID で YAML を特定

```bash
grep -rl "<TEMPLATE_ID>" /tmp/engage_html2txt/templates/<workspace_name>/
```

- ヒットした YAML がチェック対象
- YAML 内には複数 UUID（`utm.id`、リソースID等）が現れるので、`id:` 行のコンテキストを必ず確認すること

### Step 6: HTML 読み込み + 画像内テキスト分析

YAML 内の `email.html_file` を Read。HTML から：

1. **テキスト抽出**: `<script>/<style>` を除き、テーブルレイアウトを保ちつつ意味のあるテキストを取得
2. **画像URLの収集**: `<img src="...">` のURLを全て列挙
3. **画像内テキストの読み取り** (alt + vision の両方併用):
   - **alt属性が記載されている場合**: alt属性のテキストを優先採用
   - **alt属性が無い／不十分な場合**: 画像URLを Read ツールで読み込み、Claude のvision機能で画像内文字を読み解く
4. **リンク収集**: `<a href="...">` のURLとアンカーテキストをペアで取得
5. **構造把握**: 見出し、商品ブロック、CTA、フッターの境界を特定

```python
# 例: HTML パース
from bs4 import BeautifulSoup
soup = BeautifulSoup(html, 'html.parser')
# 画像
for img in soup.find_all('img'):
    print(img.get('src'), '|', img.get('alt'))
# リンク
for a in soup.find_all('a', href=True):
    print(a.get_text(strip=True), '|', a['href'])
```

BeautifulSoup が無ければ `html.parser` で代用してよい。

### Step 7: UTM パラメータ設定の確認（必須）

プレーンテキストを生成する前に、ユーザーに UTM パラメータを設定するか確認する。`AskUserQuestion` で：

> プレーンテキスト内のURLに UTM パラメータを設定しますか？
> - はい（設定する）
> - いいえ（HTMLのURLそのまま使用）

#### 「はい」が選ばれた場合

続けて以下の各値を確認する。デフォルト案を提示しつつ、ユーザーの指定を最優先：

| パラメータ | 用途 | デフォルト案 |
|---|---|---|
| `utm_source` | 流入元 | `email` |
| `utm_medium` | 媒体種別 | `mail_text` または `plaintext`（HTML版と区別する用途） |
| `utm_campaign` | キャンペーン名 | テンプレート名から推測（例: `femininetops260615`） |
| `utm_term` | 任意 | 空欄可 |
| `utm_content` | 任意（複数CTAの区別用） | 空欄可 |

提示の仕方：
- `AskUserQuestion` または通常のテキストで「以下の値で進めてよろしいですか？必要に応じて修正してください」と表示
- ユーザーが値を上書きしたら採用、空欄指定があればそのキーを付けない

#### URL への適用ルール

抽出した各 `<a href>` の URL に対して：

1. **既存クエリパラメータと衝突する utm_xxx は上書き**（同じキーを2回付けない）
2. **既存 URL に `?` が無ければ `?` を、有れば `&` で連結**
3. **`#` フラグメントの前に挿入**
4. **同一ドメイン内のリンクにのみ付与**。`mailto:` や外部の SNS シェア URL 等には付けない
5. **配信停止URL（`/member/` 等のオプトアウト系）には付けない**（誤計測防止）

```python
from urllib.parse import urlparse, urlunparse, parse_qsl, urlencode

TARGET_DOMAIN = "<your-domain>"  # 対象サイトのドメインに置き換える

def add_utm(url: str, utm: dict) -> str:
    if url.startswith('mailto:') or TARGET_DOMAIN not in url:
        return url
    if '/member/' in url:  # opt-out
        return url
    p = urlparse(url)
    q = dict(parse_qsl(p.query, keep_blank_values=True))
    for k, v in utm.items():
        if v:
            q[k] = v
    new_q = urlencode(q)
    return urlunparse(p._replace(query=new_q))
```

「いいえ」が選ばれた場合は HTML 上の URL をそのまま使用する（既存のクエリパラメータも保持）。

### Step 8: プレーンテキスト生成

HTML構造から推測した書式で生成する。**サンプル既定の固定テンプレートに無理に当てはめない**。HTMLの見出し階層・セクション分けを尊重しつつ、参考スタイルとして以下を使う：

#### 参考スタイル

| 要素 | プレーンテキスト表現 |
|------|---|
| メイン見出し（メルマガタイトル等） | `━━━━━━━━━━━━━━━━━━━━`（20文字）で上下を囲む |
| セクション見出し | 見出し直下に `━━━━━━━━━━━━━━━`（15文字） |
| 商品アイテム | `商品名` → `￥価格` → `URL` の3行 |
| 値引き表示 | `【XX% OFF】` を価格の前行 or 同行に |
| TOPICS的なリンク列挙 | `▽<タイトル>` の次行に URL |
| フッター区切り | `-----------------------` |
| 末尾 | 配信停止URL、発行元、コピーライト |

#### 生成ルール

- HTMLに登場するURLは省略せず全て出す（クエリパラメータ含めて完全な形）
- **Step 7 で UTM 設定が「はい」だった場合、URL は UTM 適用後の形で出力する**
- 画像内文字（vision で読み取った内容）は本文テキストに統合する。「(画像)」のような注釈は付けない
- alt がブランドロゴ等の装飾的な場合はテキスト化しない
- HTML上の重複（同じ商品が2箇所に出てくる等）は1回にまとめる
- 改行・空行はサンプルを参考に視認性を確保（連続2改行で段落区切り）
- 絵文字や `♪` `🌿` 等の記号は HTML に存在すれば残す

### Step 9: ユーザーへ表示

以下の形式で報告：

```
## メール情報
- ワークスペース: <name>
- テンプレート名: <template_name>
- 件名: <subject>

## 解析サマリ
- HTML セクション数: N
- 画像数: M (うち alt 取得: K件、vision 読取: L件)
- リンク数: P
- UTM 設定: 有り(source=xxx, medium=xxx, campaign=xxx) / 無し

## 生成したプレーンテキスト

` ` `
<生成したプレーンテキスト全文をここに>
` ` `
```

プレーンテキストは**必ず全文をそのまま** コードブロックで提示する。長さを理由に要約・省略・ファイルパス参照に置き換えてはならない。

### Step 10: Push の同意確認（必須）

ユーザーへ以下を尋ねる：

> このプレーンテキストで EngageStudio に Push してよろしいですか？
> - はい → Push を実行
> - 修正点あり → 指摘を受けて再生成
> - いいえ → Push せず終了

`AskUserQuestion` ツールを使って明示的に同意を取る。**「同意を得てから Push」がこのスキルの最重要ルール**。同意なしに `tdx engage template push` を実行してはならない。

### Step 11: Push（同意後のみ）

1. 生成したプレーンテキストを YAML と同じディレクトリに `<basename>.txt` として保存（既存の plaintext_file があればそのファイル名を踏襲）
2. YAML の `email.plaintext_file` を該当ファイル名に設定（未設定なら追加）
3. validate → dry-run → push の順で実行：

```bash
tdx engage template validate /tmp/engage_html2txt/templates/<workspace_name>/<template>.yaml
tdx engage template push /tmp/engage_html2txt/templates/<workspace_name>/<template>.yaml --dry-run
tdx engage template push /tmp/engage_html2txt/templates/<workspace_name>/<template>.yaml --yes
```

各ステップでエラーが出たら**Push を止めて**ユーザーに報告し、再同意を取る。

### Step 12: 完了報告

```
✅ Push 完了
- テンプレート: <name>
- plaintext_file: <filename>.txt
- 文字数: N
- UTM: source=xxx / medium=xxx / campaign=xxx （未設定の場合は「未設定」と記載）
```

---

## URL から ID を抽出する正規表現

```python
import re
m = re.match(r'https?://console-next\.us01\.treasuredata\.com/app/es/([0-9a-f-]+)/em/([0-9a-f-]+)', url)
workspace_id, template_id = m.group(1), m.group(2)
```

---

## 画像内テキスト読み取りの実装メモ

EngageStudio の HTML には商品画像、バナー画像、装飾画像が混在する。

| 画像種別 | alt の傾向 | 対応 |
|---|---|---|
| バナー（キャンペーン名画像） | 多くは alt 無し or ロゴ名のみ | **vision必須**: 重要文言が書かれていることが多い |
| 商品画像 | 商品名が入っていることが多い | alt 優先、不足すれば vision 補完 |
| 装飾／ロゴ | alt が無い or ブランド名 | テキスト化しない |
| アイコン（矢印等） | alt 無し or `>` 等 | テキスト化しない |

vision を呼ぶ判断基準：
- alt が空 or ブランド名のみ で、かつ画像が大きい（width / height が大きい、または `class="banner"` 等）→ vision 実行
- 商品画像で alt がある → alt のみ採用

vision 実行は `Read` ツールに画像URL（または一時保存した画像パス）を渡す。リモートURLが直接読めない場合は `curl -o /tmp/img.jpg <url>` で取得してから Read する。

---

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| `Authentication failed` | `mcp__tas__request_credential` で `td_api_production_aws` 取得 |
| workspace 名が見つからない | `tdx engage workspaces` で再確認、ID 比較を全 workspace に拡大 |
| `grep -rl <TEMPLATE_ID>` で 0 件 | `tdx engage campaign pull` 側を試す（template ではなく campaign 配下の email かもしれない） |
| `plaintext_file` が YAML に未設定 | 新規追加で OK。`<basename>.txt` を作成し、`email.plaintext_file: <basename>.txt` を YAML に追記 |
| 画像URLが `cid:` から始まる | インライン埋め込み画像。本文テキストには反映しない |
| vision で文字が読めない | 画質や言語を確認。失敗時はその旨をユーザー報告に明記し、当該画像はスキップ |
| Push が dry-run で失敗 | エラー内容をユーザーに報告、Push を中断。修正方針について再同意を取る |

---

## 重要ルール（再掲）

1. **同意なしに Push しない**。Step 10 の確認は省略不可。
2. プレーンテキスト全文をユーザーに必ず表示。要約禁止。
3. 画像内文字は alt 優先、不足は vision で補完。
4. URL は完全な形のまま保持（クエリパラメータも省略しない）。
5. **UTM パラメータは必ず Step 7 でユーザーに確認**。設定値もユーザーに見せて承認を得る。
6. サンプル書式は参考。HTML構造から書式を都度判断する。

---

## 関連スキル

- **engage-mail-check** — One-Off Campaign の HTML/プレーンテキスト整合性チェック
- **tdx-skills:engage** — Engage workspace / template / campaign の汎用操作
- **tdx-skills:tdx-basic** — tdx CLI の基本コマンド
