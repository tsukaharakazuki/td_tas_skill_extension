---
name: td-crm-pdca-automation
description: CRM施策のPDCA（Plan→Do→Check→Action）を4つのAIペルソナ（PM・分析・施策・クリエイティブ）で回すSkillセットを、Treasure AI Studio / Claude Code の作業フォルダへ対話しながらセットアップする。利用者のDB・テーブル・カラム・ID対応・売上ルール・Parent Segment・配信チャネルをヒアリングし、環境設定ファイルを生成して /crm-pdca を使える状態にする。「CRM PDCAを設定したい」「crm-pdcaをセットアップ」「td-crm-pdca-automation」「このURLを読み込んで設定して」「CRM施策のPDCAを回したい」などで発動する。
---

# td-crm-pdca-automation セットアップSkill

このファイルは **インストーラー（セットアップ担当）** です。利用者がこのフォルダのURLを渡して「設定したい」と依頼したら、以下の手順で対話しながら作業フォルダにCRM PDCA Skillを組み込みます。

PDCAそのものの進め方は `skills/crm-pdca/SKILL.md` に書かれています。セットアップ中はPDCAを開始しません。

- リポジトリ: `https://github.com/tsukaharakazuki/td_tas_skill_extension`
- このフォルダ: `td-crm-pdca-automation/`
- Raw URLの基点: `https://raw.githubusercontent.com/tsukaharakazuki/td_tas_skill_extension/main/td-crm-pdca-automation/`

## セットアップの全体像

```text
Step 0  開始の宣言と進め方の確認
Step 1  ファイルの取得（git sparse checkout、またはRaw URLを MANIFEST.txt から順に取得）
Step 2  作業フォルダの確定と既存インストールの確認
Step 3  ヒアリング（setup/HEARING.md の A〜G を順番に）
Step 4  （任意・承認制）tdx でスキーマを確認して候補を提示
Step 5  設定ファイルの生成（environment.yml / data-sources.md）
Step 6  Skill本体と projects/ の配置
Step 7  検証（プレースホルダー残り・パス・参照の確認）
Step 8  完了報告と /crm-pdca の使い方の案内
```

## 守ること

1. **推測で埋めない。** DB名・テーブル名・カラム名・Parent Segment ID・Workspace ID は、利用者の回答または利用者が承認したクエリ結果から確認できたものだけを書く。不明なものは `<TO_BE_CONFIRMED>` のまま残し、完了報告の「未確認事項」に列挙する。
2. **1回の質問は1テーマ。** `AskUserQuestion` が使える環境では選択肢付きで聞き、1回に聞くのは最大4問まで。使えない環境では番号付きの短い質問をチャットで聞く。各テーマの最後に、確定内容を箇条書きで復唱してから次へ進む。
3. **tdx は事前承認。** `tdx` コマンドを実行する前に、実行するコマンドと目的を示して承認を取る。セットアップ中に実行してよいのは、DB・テーブル・スキーマの一覧取得や、`LIMIT` 付きのサンプル確認など **読み取り専用** の操作だけ。セグメント作成、配信、Workflowの実行やpushは行わない。
4. **既存ファイルを壊さない。** 作業フォルダに既に `.claude/skills/crm-pdca/` や `projects/` がある場合は、上書き・差分更新・中止を利用者に選んでもらう。`projects/` 配下の既存プロジェクトと `learnings.md` は、どの場合も上書きしない。
5. **秘密情報を書かない。** APIキー、パスワード、個人のメールアドレスを設定ファイルやSkillに書き込まない。

## Step 0: 開始の宣言

最初に次の内容を伝えてから進めます。

```text
CRM施策PDCA Skillのセットアップを始めます。
1. Skillファイルを取得します
2. 作業フォルダを確認します
3. お使いのデータ環境について、7つのテーマ（A〜G）で質問します（10〜15分程度）
4. 回答から設定ファイルを作り、/crm-pdca で起動できる状態にします
分からない項目は「後で」と答えていただければ、未確認として残して先に進めます。
```

## Step 1: ファイルの取得

次の順で試します。

**方法A: git が使える場合（推奨）**

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/tsukaharakazuki/td_tas_skill_extension.git /tmp/td_tas_skill_extension
cd /tmp/td_tas_skill_extension && git sparse-checkout set td-crm-pdca-automation
```

**方法B: git が使えない場合**

`MANIFEST.txt` を Raw URL で取得し、記載された各ファイルを `<Raw URLの基点><パス>` から取得して、同じ相対パスで一時フォルダに保存する。

取得後、`setup/HEARING.md`、`setup/environment.template.yml`、`setup/data-sources.template.md` を読む。

## Step 2: 作業フォルダの確定

- 作業フォルダ ＝ `.claude/skills/` と `projects/` を置くフォルダ。Treasure AI Studio では通常、現在のセッションの作業フォルダ（カレントディレクトリ）。
- 現在のフォルダを候補として提示し、そのままでよいか確認する。
- 既に `.claude/skills/crm-pdca/config/environment.yml` がある場合は「再設定（ヒアリングをやり直す）／一部だけ変更／中止」を確認する。一部だけ変更の場合は、既存の値を見せて変更するテーマだけ聞き直す。

## Step 3: ヒアリング

`setup/HEARING.md` の **A〜G** を順番に進めます。各テーマの回答を `environment.yml` の対応キーにメモしながら進めます。

| テーマ | 内容 | 主な書き込み先 |
|---|---|---|
| A | 会社・ブランド・タイムゾーン・通貨 | `organization` |
| B | 顧客（会員）マスタ | `tables.customer` / `columns.customer` |
| C | 購買（注文）データと売上ルール | `tables.purchase` / `columns.purchase` / `business_rules` |
| D | Webアクセスログと配信経由流入の特定方法 | `tables.weblog` / `columns.weblog` |
| E | ID対応表（Web・購買・会員・配信のIDのつながり） | `id_mapping` |
| F | セグメント・配信の基盤（Parent Segment、Engage、CJO、チャネル、配信結果集計） | `audience` / `delivery` / `engage_analytics` |
| G | 連携Skill、既定のペルソナ業務範囲、配信ルール、法務チェック | `related_skills` / `defaults` / `compliance` |

- 利用者が「ない」と答えたテーブルは `enabled: false` にし、そのテーブルを使う分析が使えないことを一言伝える（例：Webログがない場合はCheckのWeb流入・サイト内行動の分析が省略になる）。
- 顧客マスタに RFM 系の集計済みカラム（最終購入からの日数、累計購入回数、LTV）がない場合は、購買データから算出する方針を `derived_metrics` に記録する。

## Step 4: スキーマ確認（任意・承認制）

利用者が「テーブル名は分かるがカラムは分からない」と答えた場合や、確認を希望した場合のみ行います。

1. 実行予定のコマンドを提示し、承認を得る。例:
   - `tdx databases` / `tdx tables <db>`
   - `tdx describe <db>.<table>`（スキーマ表示）
   - `tdx query "SELECT * FROM <db>.<table> LIMIT 5"`（`time` があるテーブルは `TD_INTERVAL` で直近に絞る）
2. 結果から、各項目に当てはまりそうなカラムを **候補として** 提示し、利用者に選んでもらう。カラム名が似ているだけで確定しない。
3. tdx が使えない環境では、利用者にテーブル定義やサンプルを貼ってもらう。

## Step 5: 設定ファイルの生成

1. `setup/environment.template.yml` をコピーし、ヒアリング結果で埋めて `.claude/skills/crm-pdca/config/environment.yml` として保存する。
2. `setup/data-sources.template.md` をコピーし、冒頭の `SETUP-NOTE` コメントを削除したうえで、`{{...}}` 形式のプレースホルダーをすべて `environment.yml` の値で置き換えて `.claude/skills/crm-pdca/reference/data-sources.md` として保存する。
   - ここに入る定番SQL（休眠分布・F2転換率・ブランド別購買者数・配信経由流入）は、実際のテーブル名・カラム名に置き換えた **そのまま実行できる形** にする。
   - 使えないテーブルに依存するSQLは、セクションごと「この環境では利用不可（理由）」に置き換える。
3. 生成した2ファイルの要点（使うテーブル、ID対応、売上ルール、Parent Segment、チャネル）を一覧で見せ、最終確認を取る。

## Step 6: Skill本体の配置

取得したファイルを、作業フォルダに次のように配置します。

| 取得元（このフォルダ内） | 配置先（作業フォルダ） |
|---|---|
| `skills/crm-pdca/` | `.claude/skills/crm-pdca/` |
| `skills/crm-plan/` | `.claude/skills/crm-plan/` |
| `skills/crm-do/` | `.claude/skills/crm-do/` |
| `skills/crm-check/` | `.claude/skills/crm-check/` |
| `skills/crm-action/` | `.claude/skills/crm-action/` |
| `projects/_index.md`, `projects/learnings.md`, `projects/_archive/` | `projects/`（**既存ファイルがあれば配置しない**） |

Step 5 で生成した `config/environment.yml` と `reference/data-sources.md` は、Skill本体の配置で上書きされないようにする（配置 → 生成の順でもよい）。

`.claude/skills/crm-pdca/config/setup_log.md` に、セットアップ日、取得元のコミットまたは取得日時、未確認事項を記録する。

## Step 7: 検証

次を確認し、問題があれば修正するか未確認事項として報告します。

- `environment.yml` がYAMLとして読み込める。
- `data-sources.md` に `{{` が残っていない。
- `environment.yml` の `<TO_BE_CONFIRMED>` を一覧化する（残っていてもよいが、報告必須）。
- `.claude/skills/` 配下の各 SKILL.md が存在し、`crm-pdca/phases/*.md` から参照されるファイル（`config/environment.yml`、`reference/data-sources.md`、`templates/*`、`personas/*`）がすべて存在する。
- `projects/_index.md` と `projects/learnings.md` が存在する。
- 有効なテーブルについて、利用者が承認すれば `SELECT COUNT(*) ... WHERE TD_INTERVAL(time, '-1d', '<timezone>')` 程度の軽い疎通確認を行う（任意）。

## Step 8: 完了報告

次の順で簡潔に報告します。

1. **配置したもの** — 作業フォルダ内のパス
2. **確定した設定** — テーブル、ID対応、売上ルール、Parent Segment、チャネル、配信結果集計の有無
3. **未確認事項** — `<TO_BE_CONFIRMED>` の項目と、それが影響するフェーズ
4. **使い方**

```text
/crm-pdca    … PMが起動し、プロジェクト選択→フェーズ→ペルソナの業務範囲を確認して開始
/crm-plan    … Planフェーズだけを開始
/crm-do      … Doフェーズだけを開始
/crm-check   … Checkフェーズだけを開始
/crm-action  … Actionフェーズだけを開始
```

環境が変わったときは、このフォルダのURLを再度読み込んで「CRM PDCAの設定を変更したい」と依頼すれば、Step 2 の「一部だけ変更」から再開できます。
