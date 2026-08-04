---
name: html-dashboard-mail-workflow
description: Treasure AI Studioで作成したHTMLダッシュボードをTreasure Workflow（Digdag）のmail>オペレーターでメール送信するときに使用する。汎用Workflowプロジェクトの新規作成・既存プロジェクト再利用、ダッシュボードごとのdigファイル分割、HTMLテンプレート配置、検証、デプロイ、安全な送信確認を支援する。
---

---
name: html-dashboard-mail-workflow
description: Treasure AI Studioで作成したHTMLダッシュボードをTreasure Workflow（Digdag）のmail>オペレーターでメール送信するときに使用する。汎用Workflowプロジェクトの新規作成・既存プロジェクト再利用、ダッシュボードごとのdigファイル分割、HTMLテンプレート配置、検証、デプロイ、安全な送信確認を支援する。
---

# HTMLダッシュボード メール送信Workflow

Treasure AI Studioで作成したHTMLダッシュボードを、Treasure Workflow（Digdag）の`mail>`オペレーターでメール送信するための汎用Skillです。

Workflowはダッシュボードごとに新規プロジェクトを作成せず、1つのプロジェクトを継続利用します。宛先、件名、スケジュール、内容が異なる場合は、ダッシュボードごとに`.dig`ファイルを分けます。

## 基本方針

- HTMLはプロジェクト内の`templates/`などに配置し、`mail>:`から相対パスで参照する。
- HTMLメールには`html: true`を設定する。
- `to`、`cc`、`bcc`は、1件でもYAML配列にする。
- ダッシュボードまたは宛先グループごとに`.dig`ファイルを分割する。
- プロジェクトがない場合だけ新規作成する。
- 既存プロジェクトでは`manifest.yml`、既存Workflow、クエリ、テンプレートを維持し、新しいファイルを追加する。
- APIキーやSMTPパスワードを`.dig`に直接書かない。
- メール送信前に設定検証と送信先確認を行う。

## 事前確認

次を確認する。未指定の場合は実在しないプレースホルダーを使用し、置換項目として示す。

1. Workflowプロジェクト名と存在有無
2. ダッシュボード名
3. HTMLファイルまたはHTML本文
4. 追加する`.dig`ファイル名
5. `to`、必要に応じて`cc`、`bcc`
6. 送信元、件名、タイムゾーン、スケジュール
7. HTML内のJavaScript、外部CSS、画像、フォントの有無
8. Workflow内でHTML生成が必要かどうか

## 手順

### 1. プロジェクトを確認して再利用する

- まずローカルのWorkflowプロジェクトを確認する。
- 既存プロジェクトがあれば、そのプロジェクトを利用する。
- TD上にのみ存在する場合は、pullまたは同期してから編集する。
- 存在しない場合だけWorkflow作成機能で新規作成する。
- 新しい`.dig`ファイル名が既存Workflow名と重複しないことを確認する。
- 無関係な既存ファイルを上書きしない。

推奨構成:

```text
html_dashboard_mail/
├── manifest.yml
├── dashboard_daily.dig
├── dashboard_weekly.dig
└── templates/
    ├── dashboard_daily.html
    └── dashboard_weekly.html
```

`.dig`とHTMLは対応が分かる名前にする。例えば`dashboard_daily.dig`は`templates/dashboard_daily.html`を参照する。

### 2. `.dig`ファイルを追加する

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

宛先が異なる場合は、次のようにファイルを分ける。

```text
dashboard_daily.dig
dashboard_weekly.dig
dashboard_management.dig
```

Studioから出力したHTMLは、原則として別ファイルで管理する。短いHTML以外では`data: |`によるインライン埋め込みを避ける。

Workflow内でクエリやHTML生成が必要な場合は、`+send_dashboard`の前にタスクを置き、`mail>:`が参照する場所に最終HTMLを作成する。Treasure Data Workflowでは`sh>`を使わず、対応するTDオペレーターまたは`py>`を使用する。

### 3. メールHTMLを確認する

メールクライアントはブラウザと異なるため、次を確認する。

- JavaScriptやインタラクティブなグラフは動作しない可能性が高い。
- 外部CSS、画像、フォントがブロックされる場合がある。
- CSSは可能な範囲でインライン化する。
- 必要に応じてグラフを静的画像または静的HTMLにする。
- HTMLのサイズが大きすぎないか確認する。

HTML内の`${...}`がJavaScriptテンプレート用の場合、Digdag変数展開と衝突する可能性があるため、エスケープまたは記法変更を行う。

### 4. デプロイ前に検証する

- YAMLの構文とインデントが正しい。
- `mail>:`のHTMLファイルが存在する。
- `html: true`が設定されている。
- `to`、`cc`、`bcc`が配列になっている。
- 送信先、件名、送信元、タイムゾーン、スケジュールが正しい。
- 認証情報やトークンが含まれていない。
- `.dig`ファイル名が一意である。
- 既存Workflowを意図せず変更していない。
- HTMLがメールクライアントで表示可能である。

設定確認には、可能な限り`tdx wf validate`などの検証コマンドを使う。検証のためだけに実際のWorkflowを実行しない。

### 5. デプロイと送信

push前に、追加・変更するWorkflow名とファイルを提示する。既存プロジェクトの場合は、既存Workflowを維持していることも示す。

Workflowの実行は外部へのメール送信を伴う。実行前にWorkflow名、実行方法、送信元、宛先、送信範囲を明示し、明示的な確認を得る。利用可能なら先にdry-runまたはプレビューを行う。`-y`などで確認を回避しない。

## 出力形式

次の順で出力する。

1. 構成方針
2. プロジェクト構成
3. 作成・追加する`.dig`ファイル
4. HTMLテンプレート、または提供HTMLをそのまま配置した旨
5. セットアップ・検証コマンド
6. デプロイ手順
7. デプロイ前の置換項目

既存プロジェクトでは「維持したファイル」と「追加したファイル」を分ける。実行していないpushやメール送信を完了済みとは書かない。

## 例

### 既存プロジェクトへの追加

`exec_reports`に経営会議用ダッシュボードを追加する場合、既存ファイルを維持して次を追加する。

```text
exec_reports/
├── manifest.yml                 # 維持
├── existing_report.dig          # 維持
├── management_meeting.dig       # 追加
└── templates/
    └── management_meeting.html  # 追加
```

### 新規プロジェクト

プロジェクトがない場合は、プロジェクトを1つ作成し、`manifest.yml`、日次用`.dig`、HTMLテンプレートを配置する。宛先が未指定ならプレースホルダーのままにし、メール送信は実行しない。

## 注意事項

- 機密性のある宛先は、概要ではマスキングする。
- 既存プロジェクトの命名規則や`manifest.yml`をサンプルより優先する。
- 同じ宛先でもスケジュールや件名が異なる場合は、原則として`.dig`を分ける。
- 複数ダッシュボードを1通にまとめるのは、利用者が明示的に希望した場合だけにする。
