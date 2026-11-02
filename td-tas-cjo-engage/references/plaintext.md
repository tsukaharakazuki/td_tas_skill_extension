# プレーンテキスト版の作成・整合性チェック

出典: engage-html-to-plaintext / engage-mail-check を統合。対象はテンプレート（`em`）、One-Off Campaign（`ooc`）、Always-On Campaign（`aoc`）のメール。

**最重要ルール**
1. 生成したプレーンテキストは**全文をそのまま**コードブロックで提示する（要約・省略・ファイルパスだけの提示は禁止）。
2. **UTM 付与の有無と値を必ず事前に確認**する。
3. **同意なしに push しない**。push 前に validate → dry-run を通す。

## 1. 対象の特定

```bash
python3 scripts/parse_console_url.py "<Console URL>"
# engage_workspace_id / engage_kind (email_template | one_off_campaign | always_on_campaign) / engage_resource_id
```

ワークスペース名の特定（ID → 名前）:

```bash
tdx engage workspaces
tdx engage workspace show "<候補名>" --full --json    # data.id と照合
```

候補が多い場合は、利用者やプロジェクトメモ（`templates/project-memo.yml`）の命名規則から推測して先に照合する。

## 2. pull して該当 YAML を見つける

```bash
mkdir -p ./engage && cd ./engage
tdx engage template pull "<workspace>" --yes                     # テンプレート
tdx engage campaign pull "<workspace>" --yes                     # One-Off
tdx engage always-on-campaign pull "<workspace>"                 # Always-On（tdx のバージョンで対応状況を確認）
grep -rl "<resource_id>" ./templates ./campaigns ./always-on-campaigns 2>/dev/null
```

- 1つの YAML に複数の UUID（`utm.id`、テンプレート参照など）が出るので、ヒット行が `id:` かどうかを確認する。
- 0件なら別種別（template ↔ campaign）を pull して再検索。
- `--name "<名前>"` で1件だけ pull もできる。

YAML の該当箇所:

```yaml
# template
html_file: xxx.html
plaintext_file: xxx.txt      # 無ければ未設定
# campaign / always-on campaign
email:
  template: ref:<template>
  subject: ...
  html_file: xxx.html
  plaintext_file: xxx.txt
```

## 3. HTML 解析

```bash
python3 -I scripts/html_extract.py <file.html> \
  [--utm source=email,medium=plaintext,campaign=<slug>] [--domain <自社ドメイン>] [--optout-pattern /member/]
```

出力の `text_blocks`（本文順）、`images`（`needs_vision: true` は画像内文字を読む）、`links`（UTM 付与後URL）、`liquid_tags` を使う。

画像内テキスト:

| 画像 | 対応 |
|---|---|
| バナー（alt 無し / ロゴ名のみ、横幅大） | **vision で読む**。重要文言が多い |
| 商品画像（alt に商品名） | alt を採用、不足時のみ vision |
| ロゴ・装飾・矢印アイコン | テキスト化しない |
| `cid:` 埋め込み | 反映しない |

vision はリモートURLを直接読めない場合 `curl -sSfo /tmp/engage_img/<n>.jpg "<url>"` で保存して Read する。読めなかった画像は報告に明記してスキップ。

## 4. UTM の確認（必須・AskUserQuestion）

> プレーンテキスト内のURLに UTM パラメータを設定しますか？（はい / いいえ）

「はい」の場合、既定案を見せて確認:

| キー | 既定案 |
|---|---|
| `utm_source` | `email` |
| `utm_medium` | `plaintext`（HTML版と区別） |
| `utm_campaign` | テンプレート名から推測 |
| `utm_term` / `utm_content` | 空欄可 |

付与ルール: 同名キーは上書き、`#` の前に挿入、自社ドメインのみ、`mailto:` / SNS共有 / **配信停止URL** / Liquid 生成URL（`{{...}}`）には付けない。
Engage 側の UTM 設定（campaign の `utm:`）が有効な場合、二重付与にならないか利用者に確認する。

## 5. 生成ルール

HTML の見出し階層・セクションを尊重する。下記は参考書式で、固定テンプレートに押し込まない。

| 要素 | 表現 |
|---|---|
| メイン見出し | `━━━━━━━━━━━━━━━━━━━━`（20字）で上下を囲む |
| セクション見出し | 直下に `━━━━━━━━━━━━━━━`（15字） |
| 商品 | `商品名` → `￥価格` → `URL` の3行（値引きは `【XX% OFF】`） |
| リンク列挙 | `▽<タイトル>` の次行に URL |
| フッター区切り | `-----------------------` |
| 末尾 | 配信停止URL、発行元、コピーライト |

- URL は省略せず完全な形（クエリ含む）。UTM「はい」なら付与後の URL。
- **`{{profile.xxx}}` などの Liquid タグはそのまま残す**（変数定義はテンプレートの `variables` と共通）。
- 画像内文字は本文に統合（「(画像)」等の注釈は付けない）。重複ブロックは1回に。
- 絵文字・記号は HTML にあれば残す。段落は空行で区切る。

## 6. 提示フォーマット

```
## メール情報
- ワークスペース / 種別 / 名前 / 件名

## 解析サマリ
- セクション数 N / 画像 M（alt K件、vision L件、読取不可 X件）/ リンク P
- UTM: 有り(source=…, medium=…, campaign=…) / 無し

## 生成したプレーンテキスト
（全文をコードブロックで）
```

続けて `AskUserQuestion`: 「この内容で push してよいですか？」— はい / 修正点あり / いいえ。

## 7. push（同意後のみ）

1. YAML と同じフォルダに `<basename>.txt` を保存（既存 `plaintext_file` があればそのファイル名を踏襲）。
2. YAML に `plaintext_file: <basename>.txt` を設定（campaign / AOC は `email:` 配下）。
3. 実行:

```bash
tdx engage template validate <yaml>
tdx engage template push <yaml> --dry-run
tdx engage template push <yaml> --yes
# campaign:  tdx engage campaign validate / push --dry-run / push --yes
# AOC:       tdx engage always-on-campaign validate / push --dry-run / push
```

- dry-run の差分に**プレーンテキスト以外の変更**（HTML・件名・変数・editor_type）が出たら止めて利用者に確認する。pull 直後の YAML を編集していれば通常は出ない。
- Visual Editor（`editor_type: beefree`）のテンプレートは HTML を push で書き換えない。プレーンテキストだけの更新で HTML 差分が出る場合は、`tdx engage template update "<name>" --workspace "<ws>" --plaintext "<text>"` を代替案として提示する（dry-run が無いので実行前に再同意）。
- エラーは push を止めて報告し、修正方針に再同意をもらう。

完了報告: テンプレート名、`plaintext_file`、文字数、UTM 設定値。

## 8. HTML / プレーンテキスト整合性チェック

HTML をコピーして新しいクリエイティブを作った時に、プレーンテキストが旧内容のまま残る事故を見つける。

```bash
python3 -I scripts/check_mail_consistency.py <file.html> <file.txt> --subject "<件名>"
```

出力の `element_differences`（日付・時刻・金額・割引・会員ランク・Liquid）、`subject_values_missing_from_body`、`urls`、`sentences_only_in_txt`（旧内容残存の疑い）をもとに報告する:

```
## 整合性チェック結果
### ✅ 一致している項目
### ⚠️ 差異・不整合（件名と本文、日付、URL、金額…）
### 📋 注意（画像内テキストなど意図的な差の可能性）
```

- 画像だけで表現された文言は「TXT にだけある」と出るので、vision で確認してから不整合と判定する。
- `plaintext_file` が未設定なら「プレーンテキスト未設定」と報告し、5. の生成を提案する。
- チェックだけの依頼では何も push しない。
