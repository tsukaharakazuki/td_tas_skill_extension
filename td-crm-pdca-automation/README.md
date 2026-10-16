# td-crm-pdca-automation

CRM施策の **Plan → Do → Check → Action** を、4つのAIペルソナ（PM・分析・施策・クリエイティブ）と人間の意思決定で回すための Skill セットです。Treasure AI Studio / Claude Code で動作します。

**📖 [解説ページを開く（CRM施策PDCA Skill 活用ガイド）](https://tsukaharakazuki.github.io/td_tas_skill_extension/td-crm-pdca-automation/)**

4つのペルソナ、PDCAの各フェーズ、人が決める承認ポイント、セットアップで確認する内容を図解しています。

> **保存先について:** Treasure AI Studio では本人しかアクセスできない `my` フォルダが仕様として作成されます。ここに置くと他のメンバーと共有できないため、このSkillは Skill本体・設定・成果物・`MEMORY.md` を **必ず `my` 以外の共有作業フォルダ** に置きます。現在のフォルダが `my` の中なら、`my` と同じ階層に共有用フォルダを作ってからセットアップします。
>
> **引き継ぎについて:** 作業は段階を追って、担当者をまたいで進みます。共有作業フォルダ直下の `MEMORY.md` に、いつ・誰が・何をして・次に何をするかを時系列で記録し、各Skillは起動時にこれを読んで続きから始めます。

特定企業のテーブル定義は含んでいません。初回に対話形式のセットアップを行い、利用者のデータ環境（テーブル・カラム・ID対応・売上ルール・Parent Segment・配信チャネル）を設定ファイルに落とし込んでから使います。

## セットアップ（Treasure AI Studio）

チャットで次のように依頼してください。

```text
https://github.com/tsukaharakazuki/td_tas_skill_extension/tree/main/td-crm-pdca-automation
このURLを読み込んで、CRM PDCAの設定をしたいです。
```

AIが `SKILL.md`（セットアップ手順）を読み込み、次の流れで進めます。

1. Skillファイルを取得する
2. 共有作業フォルダを確定する（`my` 配下なら `my` と同じ階層に新しいフォルダを作成。既存のインストールがあれば上書き・一部変更・中止を選択、`my` 配下の既存インストールはコピーで移行）と、担当者名の確認
3. 7つのテーマ（A〜G）について質問する — 所要時間は10〜15分程度
   - A 組織・タイムゾーン・通貨
   - B 顧客（会員）マスタ
   - C 購買データと売上ルール（キャンセル除外・金額の重複排除）
   - D Webアクセスログと配信経由流入の判定
   - E ID対応（Web・購買・会員・配信）
   - F セグメント・配信基盤（Parent Segment、Engage Studio、CJO、チャネル、配信結果集計）
   - G 連携Skill・ペルソナの業務範囲・配信上限・法務チェック
4. 必要に応じて、承認を得たうえで `tdx` でスキーマを確認し、カラムの候補を提示する（読み取り専用）
5. `config/environment.yml` と `reference/data-sources.md`（この環境用の分析ガイドラインと定番SQL）を生成する
6. Skill 本体を共有作業フォルダの `.claude/skills/` に、`projects/` と `MEMORY.md` を共有作業フォルダ直下に配置する
7. 検証し（`my` 配下に置いていないことも確認）、`MEMORY.md` にセットアップ内容を記録して、未確認事項と使い方を報告する

分からない項目は「後で」と答えれば `<TO_BE_CONFIRMED>` として残り、その値が必要な作業の直前にAIが改めて確認します。

## 使い方（セットアップ後）

```text
/crm-pdca    ← メイン起動（全フェーズ）
/crm-plan    ← Plan フェーズ単独起動
/crm-do      ← Do フェーズ単独起動
/crm-check   ← Check フェーズ単独起動
/crm-action  ← Action フェーズ単独起動
```

### 4ペルソナ

| ペルソナ | プレフィックス | 役割 |
|---|---|---|
| プロジェクトマネージャー | 【PM】 | 全体進行・意思決定のファシリテート |
| 分析担当 | 【分析】 | データ分析・KPI評価 |
| 施策担当 | 【施策】 | セグメント設計・配信実行 |
| クリエイティブ企画 | 【CR】 | コピー・訴求軸・A/Bテスト設計 |

各ペルソナの業務範囲（`full_auto` / `consult` / `human_led`）はプロジェクトごとに決めます。

Engage Studio の既存アセットURLをブラウザから開けない場合は、【CR】がURLのWorkspace/Template IDを `tdx engage` で照合し、テンプレートをpullして確認します。詳細は `skills/crm-pdca/personas/creative-planner.md` を参照してください。テンプレート更新とキャンペーン配信は別操作で、それぞれ明示承認が必要です。

### スキップできない4つの承認ポイント

1. 施策方向性の確定
2. KPI（評価指標）の確定
3. セグメント＆クリエイティブの最終承認
4. 次サイクルの意思決定（継続 / 修正 / 中止 / 完了）

`tdx` の実行と配信（外部送信）は、必ず事前に承認を取ってから行います。

### 対応施策タイプ

休眠掘り起こし / 新作キャンペーン / F2転換 / クロスセル / LTV向上・VIP施策 / 離反予防 / 季節イベント

複数施策を並行して管理でき、学びは `projects/learnings.md` に蓄積して横展開します。

### MEMORY.md — 時系列の作業記録

共有作業フォルダ直下の `MEMORY.md` は、ワークスペース全体の作業記録です。

- **現在の状況**（上書き）: 進行中プロジェクトとフェーズ、承認待ち、未確認事項、次にやること
- **更新履歴**（追記のみ・古い順）: セットアップ、設定変更、プロジェクト立ち上げ、フェーズ開始・完了、承認①〜④、配信、学びの追記、アーカイブ、中断・交代（handover）

各エントリには日時・担当者・内容・決定事項・変更ファイル・次の作業を書きます。`/crm-pdca` などの各Skillは起動時に MEMORY.md を読んで「前回は誰がどこまで進めたか」を伝え、担当者名を確認してから始めます。人が直接追記しても構いません。書式は `skills/crm-pdca/reference/workspace-and-memory.md` を参照してください。

## ファイル構成

```text
td-crm-pdca-automation/
├── SKILL.md                         # セットアップ（対話式インストール）手順
├── README.md
├── MANIFEST.txt                     # git が使えない環境向けのファイル一覧
├── setup/
│   ├── HEARING.md                   # ヒアリング項目（A〜G）
│   ├── MEMORY.template.md           # 作業記録（MEMORY.md）のひな形
│   ├── environment.template.yml     # 環境設定テンプレート
│   └── data-sources.template.md     # 分析ガイドライン・定番SQLテンプレート
├── skills/                          # 共有作業フォルダの .claude/skills/ に配置される本体
│   ├── crm-pdca/
│   │   ├── SKILL.md
│   │   ├── phases/                  # plan / do / check / action
│   │   ├── personas/                # PM / 分析 / 施策 / CR
│   │   ├── reference/project-management.md
│   │   ├── reference/workspace-and-memory.md  # 保存先（my 以外）と MEMORY.md のルール
│   │   └── templates/               # project_state.json と各レポート
│   ├── crm-plan/SKILL.md
│   ├── crm-do/SKILL.md
│   ├── crm-check/SKILL.md
│   └── crm-action/SKILL.md
└── projects/                        # 共有作業フォルダに配置される管理用フォルダ
    ├── _index.md
    ├── learnings.md
    └── _archive/
```

セットアップ後の共有作業フォルダ（`my` 以外）:

```text
<共有作業フォルダ>/                  # 例: my と同じ階層の crm-pdca/
├── MEMORY.md                        # 時系列の作業記録（担当者間の引き継ぎ）
├── .claude/skills/
│   ├── crm-pdca/
│   │   ├── config/environment.yml   # 生成: 環境設定
│   │   ├── config/setup_log.md      # 生成: セットアップ記録・未確認事項
│   │   ├── reference/data-sources.md# 生成: この環境用の分析ガイドライン・定番SQL
│   │   └── ...
│   └── crm-plan/ crm-do/ crm-check/ crm-action/
└── projects/
    ├── _index.md
    ├── learnings.md
    └── <project-id>/                # PDCA実行中に生成
```

## 設定の変更

テーブルや配信ツールが変わったときは、同じURLを読み込んで「CRM PDCAの設定を変更したい」と依頼してください。既存の設定を表示したうえで、変更したいテーマだけを聞き直します。`projects/` 配下の既存プロジェクトと学びログは上書きされません。

`config/environment.yml` を直接編集しても構いません。その場合は `reference/data-sources.md` の該当箇所も合わせて更新してください。

## 手動インストール（Claude Code）

共有作業フォルダ（`my` 以外。チームで共有するリポジトリやフォルダ）で行います。

1. このフォルダの `skills/` 以下を、プロジェクトの `.claude/skills/` にコピー
2. `projects/` をプロジェクトルートにコピー
3. `setup/MEMORY.template.md` をプロジェクトルートに `MEMORY.md` としてコピーし、`{{...}}` を記入
4. `setup/environment.template.yml` を `.claude/skills/crm-pdca/config/environment.yml` にコピーして値を記入（`workspace.root` に共有作業フォルダの絶対パス）
5. `setup/data-sources.template.md` の `{{...}}` を記入値で置き換え、`.claude/skills/crm-pdca/reference/data-sources.md` として保存
6. `/crm-pdca` で起動

## 連携Skill（任意）

同じリポジトリの次のSkillと連携します。

- `cjo-journey-tips` — CJO ジャーニー構築（Plan / Do）
- `html-dashboard-mail-workflow` — Check レポートの HTML 化とメール送付（Check）

社内のSQLガイドラインやセグメント作成のSkillがあれば、セットアップ時に登録できます（`related_skills`）。

## 更新履歴

| 日付 | 内容 |
|---|---|
| 2026-10-16 | 保存先を `my` 以外の共有作業フォルダに限定（`workspace.root`、書き込み前のパス確認、`my` 配下からの移行手順）。時系列の作業記録 `MEMORY.md` を追加し、各Skillの起動時に読み込み・承認やフェーズ完了・交代時に追記するようにした。`environment.yml` を schema_version 2 に更新 |

### 旧バージョンでセットアップ済みの場合

同じURLを読み込んで「CRM PDCAを最新版に更新したい」と依頼してください。`workspace` 設定と `MEMORY.md` が追加されます。既存の設置場所が `my` 配下の場合は、共有作業フォルダへのコピーを提案します（元のファイルは削除しません）。
