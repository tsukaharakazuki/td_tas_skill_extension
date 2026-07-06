---
name: engage-mail-check
description: 'Use when the user wants to verify that an Engage Studio email''s HTML content and plain text content are consistent. Triggers on EngageStudio URLs (`console-next.us01.treasuredata.com/app/es/.../ooc/.../...`), or phrases like "EngageStudioのメール確認", "HTMLとプレーンテキストの整合性", "メールの差分チェック", "プレーンテキストが古いままになっていないか", "Engageキャンペーンのチェック", "メール配信前チェック".'
---

# EngageStudio HTML / プレーンテキスト整合性チェック

EngageStudio で配信予定のメール（One-Off Campaign）について、**HTMLメール本文** と **プレーンテキスト本文** に齟齬がないか確認するスキル。HTML をコピペして新規クリエイティブを作成した際に、プレーンテキストが旧メール内容のままになっているケースを発見することが主目的。

---

## 入力

ユーザーは EngageStudio のキャンペーン編集画面 URL を提示する。形式は以下：

```
https://console-next.us01.treasuredata.com/app/es/<WORKSPACE_ID>/ooc/<CAMPAIGN_ID>/<tab>
```

- `<WORKSPACE_ID>`: Engage workspace の UUID
- `<CAMPAIGN_ID>`: One-Off Campaign の UUID（`ooc` = One-Off Campaign）
- `<tab>`: 編集画面のタブ（`ta` など。判定には使わない）

---

## 実行フロー

ユーザーから URL を受け取ったら、以下を順に実行する。各ステップ完了後にユーザーへ進捗を簡潔に通知する。

### Step 1: URL から ID を抽出

```
WORKSPACE_ID = URL の /app/es/ 直後の UUID
CAMPAIGN_ID  = URL の /ooc/ 直後の UUID
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

を全コマンドの先頭に付与する。

### Step 3: workspace 名を特定

`tdx engage workspaces` で workspace 一覧を取得後、各 workspace に対して下記を実行し、`WORKSPACE_ID` と一致する workspace 名を見つける：

```bash
tdx engage workspace show "<workspace_name>" --full --json 2>&1 | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
```

**効率化**: 全 workspace を逐次照合するとループが多くなる。プロジェクトコンテキストに workspace 命名規則がある場合は推測をかける。一致が出るまで for ループで回す（前例では 20 件程度）。

### Step 4: campaigns を一括 pull

特定した workspace から全キャンペーンを YAML+HTML+TXT セットで pull する：

```bash
mkdir -p /tmp/engage_check && cd /tmp/engage_check && \
  tdx engage campaign pull "<workspace_name>" --yes
```

pull 先: `/tmp/engage_check/campaigns/<workspace_name>/`

### Step 5: CAMPAIGN_ID で YAML を特定

```bash
grep -rl "<CAMPAIGN_ID>" /tmp/engage_check/campaigns/<workspace_name>/
```

ヒットした YAML がチェック対象。

**注意**: campaign YAML 内には複数の UUID が出現する（`utm.id`, テンプレート ID など）。`grep` で該当する `id:` 行のコンテキストも確認すること。

### Step 6: HTML / プレーンテキストを抽出

YAML 内の `email.html_file` と `email.plaintext_file` を読み取り、対応するファイルを Read する。

```yaml
email:
  template: ref:<template_name>
  subject: <件名>
  html_file: <name>.html
  plaintext_file: <name>.txt
```

### Step 7: ユーザーへ通知（抽出結果）

以下を提示する：

- **キャンペーン名 / ワークスペース / 件名**
- **HTML の主要セクション一覧**（テーブル形式: セクション / 内容要約）
- **プレーンテキストの全文**（必ず全文をそのままテキストとしてユーザーに表示すること。長さを理由に要約・省略・ファイルパス参照に置き換えてはならない。コードブロック ``` で囲んで提示する）

その後、Step 8 の差分チェックに進む。

### Step 8: 差分チェック（重要要素 + 全文）

#### A. 重要要素チェック（必須）

以下を HTML / プレーンテキスト / 件名 の 3 者で照合し、不整合があれば全て列挙する：

| チェック項目 | 抽出方法 |
|---|---|
| **日付** | `\d{4}/\d{1,2}/\d{1,2}`、`\d{1,2}月\d{1,2}日`、曜日記号 |
| **時刻 / 期間** | `\d{1,2}:\d{2}`、「〜まで」「開催期間」 |
| **金額・割引率** | `[\d,]+円`、`\d+%OFF`、`\d+,\d+円OFF` |
| **会員ステージ** | VIP/GOLD/SILVER/ゴールド/シルバー など |
| **キャンペーン名 / 商品名** | 件名・見出しに含まれる固有名詞 |
| **URL** | リンク先パス |
| **件名 vs 本文** | 件名のキーワードが本文に登場するか |

#### B. 全文比較（補助）

HTML からテキストのみを抽出（python の `html.parser` などで `<script>/<style>` を除き、タグを剥がす）し、プレーンテキストと並べて：

- HTML にあるが プレーンテキストに無い文（脱落）
- プレーンテキストにあるが HTML に無い文（旧コンテンツの残存疑い）

を抽出する。HTML はテーブルレイアウトなので空白・改行が多い → 比較前に正規化（連続空白を 1 つに、空行除去）する。

```python
# 例: HTML テキスト抽出
from html.parser import HTMLParser
import re

class TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.skip = False
    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'): self.skip = True
    def handle_endtag(self, tag):
        if tag in ('script', 'style'): self.skip = False
    def handle_data(self, data):
        if not self.skip: self.parts.append(data)

p = TextExtractor()
p.feed(html_str)
html_text = re.sub(r'\s+', ' ', ' '.join(p.parts)).strip()
```

URL 抽出は `re.findall(r'https?://[^\s"<>]+', text)` で両方から集合を取り、対称差をとる。

### Step 9: 結果レポート

ユーザーへ以下の形式で報告：

```
## 整合性チェック結果

### ✅ 一致している項目
- 日付: 2026/6/11(木) - 6/14(日) （HTML / TXT 両方に存在）
- 件名キーワード「VIPクーポン」: 本文両方に存在
- ...

### ⚠️ 差異・不整合
1. **【件名と本文の不整合】** 件名に「6/11スタート」とあるが、TXT 本文の開催期間が「2026/5/30〜」と古い日付になっている
2. **【URL の不一致】** HTML には最新キャンペーンへの CTA があるが、TXT には旧キャンペーンのパスが残っている
3. **【金額の不一致】** ...

### 📋 注意（差異だが意図的かもしれない）
- HTML に画像で表示されている要素がプレーンテキストに無い（仕様上正常な可能性）
- ...
```

不整合が無い場合は「✅ 整合性に問題は検出されませんでした」とだけ伝え、確認した項目を列挙する。

---

## URL から ID を抽出する正規表現

```python
import re
m = re.match(r'https?://console-next\.us01\.treasuredata\.com/app/es/([0-9a-f-]+)/ooc/([0-9a-f-]+)', url)
workspace_id, campaign_id = m.group(1), m.group(2)
```

---

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| `Authentication failed` | `mcp__tas__request_credential` で `td_api_production_aws` を取得 |
| workspace 名が見つからない | `tdx engage workspaces` で再確認。ID 比較を全 workspace に拡大 |
| `grep -rl <CAMPAIGN_ID>` でヒット 0 | template の場合がある。`tdx engage template pull` も試す |
| `plaintext_file` が YAML に無い | プレーンテキスト未設定。ユーザーに「プレーンテキスト未設定」と通知して終了 |
| HTML テキスト抽出で文字化け | ファイルを utf-8 として読む、`html.unescape` を通す |

---

## 関連スキル

- **tdx-skills:engage** — Engage workspace / template / campaign の汎用操作
- **tdx-skills:tdx-basic** — tdx CLI の基本コマンド
