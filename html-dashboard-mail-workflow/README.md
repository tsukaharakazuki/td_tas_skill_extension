# html-dashboard-mail-workflow

Treasure Work スキル — Treasure AI Studioで作成したHTMLダッシュボードを、Treasure Workflow（Digdag）の`mail>`オペレーターでメール送信するための汎用Workflow構築支援。

## 概要

- Treasure AI StudioのHTMLダッシュボードをHTMLメールとして送信
- `mail>`オペレーターの設定とHTMLテンプレート配置
- Workflowプロジェクトがない場合の新規作成
- 既存Workflowプロジェクトへのダッシュボード追加
- ダッシュボード・宛先ごとの`.dig`ファイル分割
- デプロイ前のWorkflow検証と送信先確認
- HTMLメールでJavaScriptや外部リソースを使用する場合の注意点

## ディレクトリ構成

```text
html-dashboard-mail-workflow/
├── README.md
├── SKILL.md
└── examples/
    ├── manifest.yml
    ├── dashboard_daily.dig
    ├── dashboard_weekly.dig
    └── templates/
        ├── dashboard_daily.html
        └── dashboard_weekly.html
```

## 基本構成

```yaml
timezone: Asia/Tokyo

_export:
  mail:
    from: "sender@example.com"

+send_dashboard:
  mail>: templates/dashboard_name.html
  subject: "ダッシュボード名 - ${session_date}"
  to:
    - "recipient@example.com"
  html: true
```

## プロジェクト運用方針

Workflowプロジェクトはダッシュボードごとに新規作成せず、共通のプロジェクトを継続利用します。

サンプルや生成物には、特定顧客の会社名、顧客固有のデータベース名・テーブル名・メールアドレス・URLを記載せず、プレースホルダーを使用します。実際の環境情報は、作成時に利用者へ確認します。

プロジェクトが存在しない場合だけ、`manifest.yml`を含むプロジェクトを作成します。既存プロジェクトがある場合は、既存ファイルを維持したまま、新しい`.dig`ファイルとHTMLテンプレートを追加します。

宛先がダッシュボードごとに異なる場合は、次のように`.dig`ファイルを分けて管理します。

```text
dashboard_daily.dig
dashboard_weekly.dig
dashboard_management.dig
```

## インストール方法

### Treasure Work（グローバルスキル）

```bash
cp -r html-dashboard-mail-workflow ~/.treasure-work/.claude/skills/
```

### Treasure Work（ワークスペーススキル）

```bash
cp -r html-dashboard-mail-workflow /path/to/workspace/.claude/skills/
```

コピー後、Treasure Workを再起動するとスキルが認識されます。

## 使い方

Treasure Workのチャットで以下のように呼び出します。

```text
/html-dashboard-mail-workflow
```

または、次のように依頼します。

```text
このHTMLダッシュボードをDigdagのmailオペレーターで送信したい。
既存のWorkflowプロジェクトに、宛先別のdigファイルとして追加して。
```

## デプロイ前の注意

- `to`、`cc`、`bcc`はYAML配列で指定してください。
- `html: true`を設定してください。
- 送信者、宛先、件名、スケジュールを確認してください。
- APIキーやSMTPパスワードをWorkflowファイルに直接記載しないでください。
- 新規プロジェクトまたは`tdx.json`がない場合は`tdx wf upload <project-dir>`を使用してください。
- 既存プロジェクトで`tdx.json`を取得済みの場合は`tdx wf push`を使用してください。
- `tdx wf validate`などで検証してからデプロイしてください。
- JavaScriptやインタラクティブなグラフは、多くのメールクライアントで動作しません。
- HTML生成には、環境によって`DockerConfig is not valid for EcsCommand`エラーになる可能性があるため、`py>`を使用しないでください。HTMLはWorkflow外で生成し、Workflowは`mail>`中心に構成してください。
- 実際にメールを送信するWorkflow実行前には、送信先と送信範囲を確認してください。

## ライセンス

MIT
