# Engage メール: テンプレート / Always-On Campaign / One-Off Campaign

出典: td-tdx-engage を tdx 2026.10.4 の YAML スキーマで補正。tdx を更新したら `tdx engage <kind> validate` のエラーで差分を確認する。

**原則**: YAML とHTML（と TXT）を必ずセットで作る。push するのは YAML。validate → push `--dry-run` → preview → 承認 → push。

## 1. 差し込み変数（メールのスキーマ）を調べる

```bash
tdx engage workspace show "<ws>" --full --json       # applicableParentSegments
tdx ps desc "<親セグメント名>" -o /tmp/ps_schema.json  # customers の列・型（ビヘイビアは behaviors）
```

- `{{profile.<列名>}}` で参照できるのは、ワークスペースに割り当てた親セグメントの `customers` 列。
- 列ごとの NULL 率を確認して `default_value` を決める:

```sql
SELECT COUNT(*) AS n, COUNT(first_name) AS first_name_nonnull, COUNT(member_rank) AS member_rank_nonnull
FROM cdp_audience_<ps_id>.customers
```

| 非NULL率 | 対応 |
|---|---|
| 100% | `default_value` 任意 |
| 100%未満 | `default_value` を設定（空欄表示を防ぐ） |
| 適切な既定値が無い（性別など） | HTML 側で Liquid 条件分岐 |

```html
{% if profile.member_rank == 'GOLD' %}<p>GOLD会員さま限定</p>{% else %}<p>会員さま限定</p>{% endif %}
```

- `{{sender.email}}` は送信者由来なので `variables` 不要。
- 件名・HTML・プレーンテキストの Liquid は同じ `variables` を共有する。

## 2. テンプレート（`type: template`）

```yaml
type: template
name: "Welcome Mail 2026"
workspace: "<ws>"
subject: "{{profile.first_name}}さま、ご登録ありがとうございます"
preheader: "初回限定クーポンをお届けします"     # 最大220文字
editor_type: grapesjs                          # HTML から作る場合は必ず grapesjs
html_file: welcome-mail-2026.html
plaintext_file: welcome-mail-2026.txt          # 任意（plaintext.md）
variables:
  - name: first_name
    display_name: 名
    preview_value: "{{profile.first_name}}"    # 必須
    default_value: お客
```

| フィールド | 必須 | 注意 |
|---|---|---|
| `name` | ✔ | push はワークスペース内の名前で照合（同名は更新） |
| `editor_type` | — | `beefree`（Visual Editor）は独自JSON。HTMLから作れないので新規は `grapesjs` |
| `variables[].display_name` / `preview_value` | ✔ | テンプレートでは必須（キャンペーン側は任意） |

```bash
tdx engage template pull "<ws>" --yes                 # 既存を YAML+HTML(+TXT) で取得。--name で1件
tdx engage template validate <yaml>
tdx engage template push <yaml> --dry-run
# preview_engage_template（file_path でローカル YAML）
tdx engage template push <yaml> --yes
```

ファイル配置: `templates/<workspace-slug>/{tdx.json, *.yaml, *.html, *.txt}`。`tdx.json` に `{"engage_workspace": "<ws>"}`。

## 3. Always-On Campaign（`type: always_on_campaign`）— ジャーニーの配信先

```yaml
type: always_on_campaign
name: "CJO Welcome Stage1"
campaign_type: email                 # email | push | line | sms
workspace: "<ws>"
audience: ref:<親セグメント名>        # 親セグメント
email:
  template: ref:Welcome Mail 2026    # サーバー上のテンプレート名
  subject: "{{profile.first_name}}さま、ご登録ありがとうございます"
  preheader: "初回限定クーポンをお届けします"
  html_file: cjo-welcome-stage1.html
  plaintext_file: cjo-welcome-stage1.txt
  sender_id: "<送信者プロファイルID>"  # tdx delivery senders
  variables:
    - name: first_name
      default_value: お客
utm:
  enabled: true
  medium: email
  source: treasuredata
  campaign: cjo-welcome
```

- AOC にセグメント指定は無い。**誰に送るかはジャーニーのアクティベーションが決める**。
- tdx 2026.10 以降は AOC の pull / push / validate があり、テンプレート紐付け・送信者・UTM を YAML で扱える（cjo-journey-tips の「CLI 非対応・Console のみ」は旧版の情報）。古い tdx では `always-on-campaign create`（基本情報のみ）+ Console 設定になる。`tdx engage always-on-campaign --help` で確認。

```bash
tdx engage always-on-campaign pull "<ws>"            # --name / --type で絞り込み
tdx engage always-on-campaign validate <yaml>
tdx engage always-on-campaign push <yaml> --dry-run
tdx engage always-on-campaign push <yaml>
tdx engage always-on-campaign show "<name>" --workspace "<ws>"   # ID を取得 → memo とジャーニーの always_on_campaign_id
tdx engage campaign readiness <yaml> --workspace "<ws>"          # 送信ドメイン・送信者の準備
```

**launch / resume は配信開始操作**。Skill からは実行しない（利用者が Console で行うか、影響範囲を説明したうえで明示承認を得た場合のみ）。`delete` は DRAFT のみ可能だが、Skill からは削除しない。

## 4. One-Off Campaign（`type: campaign`）— ジャーニー外の単発配信

```yaml
type: campaign
name: "11月セール告知"
campaign_type: email                 # email | push | line
workspace: "<ws>"
audience: ref:<親セグメント名>
segment: ref:<子セグメント名>         # 見つからない場合はフォルダ付き ref:[1] Segments/Behavioral/<名前>
email:
  template: ref:<テンプレート名>
  subject: "..."
  html_file: sale-1101.html
  plaintext_file: sale-1101.txt
  sender_id: "<送信者プロファイルID>"
schedule: { start_at: "2026-11-10T10:00:00+09:00", timezone: Asia/Tokyo }
connector:
  all_columns: false
  columns: [{ column: email, source: email }]
utm: { enabled: true, medium: email, source: treasuredata, campaign: sale-1101 }
notifications: { events: [onFailure], recipients: [<TDユーザーID>] }
```

`ref:` は `template` / `audience` / `segment` で必須。`utm.id` はサーバー採番（新規では書かない）。

```bash
tdx engage campaign validate <yaml>
tdx engage campaign push <yaml> --dry-run
# preview_engage_campaign
tdx engage campaign push <yaml> --yes
tdx engage campaign readiness <yaml>
```

`tdx engage campaign launch` は**配信開始**。dry-run で対象と件数を説明し、明示承認なしに実行しない。

## 5. 画像（DAM）

```bash
tdx engage media ls [path]
tdx engage media mkdir <path>
tdx engage media upload <file>        # JPEG / PNG / GIF
```

`rm` / `rmdir` は使わない（配信済みメールの画像が切れる）。

## 6. トラブルシューティング

| 症状 | 対処 |
|---|---|
| HTML はあるのに push できない | YAML を作る（`type: template` 等） |
| 差し込みが空欄 | NULL のある列に `default_value` |
| `ref:` テンプレートが見つからない | 先にテンプレートを push。`tdx engage templates` で名前を確認 |
| セグメントが見つからない | フォルダ付き `ref:[1] Segments/.../<名前>` |
| readiness で送信ドメイン未割当 | engage-setup.md 3-3 |
| readiness で sender 未設定 | `email.sender_id` を設定（`tdx delivery senders`） |
| 認証エラー | SKILL.md「認証」の手順 |
