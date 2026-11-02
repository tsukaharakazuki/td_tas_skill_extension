# 新規ジャーニーの作成（5ステップ）

出典: td-tdx-journey（templates/step1〜4）+ cjo-journey-tips。YAML の書式は journey-validation.md、セグメントは segment-rules.md、アクティベーションは activation-engage.md。

**進め方**
- 最初に5ステップの TODO を作り、1つずつ進める。ステップを飛ばしたりまとめたりしない。
- 各ステップで「調査コマンド実行 → 不足情報を質問 → 設計を提示して**1回だけ**確認 → YAML に書く → 次へ」。確認後に「進めてよいですか？」と重ねて聞かない。
- 値は推測しない。親セグメント・列・コネクション・AOC はコマンドで確認する。

## 0. 準備

```bash
tdx sg use "<親セグメント名>"
tdx sg pull "<親セグメント名>"          # segments/<ps-slug>/ と tdx.json（フォルダ構成も取得される）
tdx sg list -r                          # Console のフォルダ構成
tdx ps desc "<親セグメント名>" -o /tmp/ps_schema.json
tdx sg fields
```

**ファイルの場所 = Console のフォルダ**。`tdx journey push` は「フォルダ + ジャーニー名」で既存ジャーニーを探す。
ジャーニーは必ずサーバー上に存在するフォルダに置く: `segments/<ps-slug>/<フォルダ>/<journey>.yml`。
YAML に `folder:` を書いても効かない（cjo-journey-tips の「フォルダが反映されない」の原因）。新しいフォルダが必要なら作成されることを dry-run で確認する。

## Step 1: 基準セグメント（ゴール・入口・マイルストーン・出口）

- ゴール: ジャーニー全体の成功条件（1つ）。
- Stage1 の `entry_criteria`: 新しいセグメント。Stage2 以降の入口は**前ステージの milestone**（新規セグメント不要）。
- `milestone`: 次ステージに進む条件。最終ステージには付けない。
- `exit_criteria`: 離脱・配信停止など。全ステージで再利用してよい。**同意（opt-in）・配信停止は entry / exit に入れる**。
- 実データで値と件数を確認してから書く（segment-rules.md 1.）。未購買条件は COUNT < 1 方式を提案。

## Step 2: 分岐・条件待ちのセグメント

| 選び方 | 使うもの |
|---|---|
| 「N日待ってから判定」 | `decision_point`（duration wait の後） |
| 「最大N日待ち、条件を満たしたら即反応」 | 条件待ち（`wait.with.condition` + timeout） |

迷ったら利用者に「すぐ反応しますか、待ってから判定しますか？」と聞く。各ブランチのセグメント（新規 / Step1 の再利用 / `excluded: true` の catch-all）を決める。

## Step 3: アクティベーション（Engage）

activation-engage.md に従う。Engage の前提（ワークスペース・送信者・AOC・コネクション）が揃っていなければ engage-setup.md へ。

- ステージ・分岐ごとに AOC を分けるか、1つの AOC + テンプレート内の Liquid 分岐にするかを確認。
- 実行タイミング: `run_after_journey_refresh: true`（一般的）か固定スケジュールかを確認。
- 列名の変更・クーポン固定値が必要なら、push 後に API PATCH が必要になることを先に伝える。

## Step 4: ジャーニー構造（1ステージずつ）

利用者に確認: ジャーニー名・説明、`reentry`、ステージ名、各ステージのフロー。
ステージごとに**フロースケッチをコメントで書いてから**ステップを書き、`tdx journey validate` を通して提示する。

```yaml
type: journey
name: Welcome Onboarding
description: 会員登録後のオンボーディング
reentry: no_reentry
segments: { ... }        # Step 1-2
activations: { ... }     # Step 3
journeys:
  - state: draft
    goal: { name: First Purchase, segment: first_purchase }
    stages:
      # Flow: Send Welcome → Wait 3 Days → Decision(Opened / Not Opened)
      #       Opened → Send Follow Up → Merge → Wait 1 Day → End
      #       Not Opened → Send Reminder → Merge
      - name: "Stage 1: Welcome"
        entry_criteria: { name: New Members, segment: new_members }
        milestone: { name: Engaged, segment: email_engaged }
        exit_criteria: [ { name: Unsubscribed, segment: unsubscribed } ]
        steps: [ ... ]
```

API 制約（validate では出ない）: 分岐の各経路に merge 前のアクティベーション、アクティベーションの後に wait。

## Step 5: 検証・プレビュー・push

```bash
tdx journey validate segments/<ps>/<folder>/<journey>.yml
tdx journey push segments/<ps>/<folder>/<journey>.yml --dry-run     # 新規作成になること
```

`preview_journey`（YAML パス指定）でフローを見せ、ステージ名・分岐・merge・end を確認してもらう（省略不可）。

```bash
tdx journey push segments/<ps>/<folder>/<journey>.yml --yes 2>&1 | tee /tmp/push.log
grep -o 'https://[^ ]*' /tmp/push.log
tdx journey list "<journey>"
tdx journey versions "<journey>"
```

push 後チェック:
1. 出力URLのジャーニーと Console で見ているジャーニーが同一か（別ジャーニーが作られていないか）。
2. `tdx journey versions` に想定外の `latest: false` が無いか。
3. `latest_activations.py` で接続先・`workspace_id`・`always_on_campaign_id`。
4. API PATCH が必要な項目（列名変更・ストリングビルダー）を activation-engage.md 5. の手順で設定。
5. Console でフォルダ・分岐条件（`excluded`）を目視。

新規ジャーニーは draft のまま引き渡す。**launch / Simulation 開始は利用者が Console で行う**。
`cjo-engage-memo.yml` にジャーニー名・ID・YAML パス・AOC を記録する。
