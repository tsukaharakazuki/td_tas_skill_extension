# Phase 1: Plan

目的: 施策の目的・ターゲット・KPI・配信設計を確定し、Doに移れる状態にする。

## ステップ全体像

```
[1] PMヒアリング
      ↓
[2] PM→分析 指示書
      ↓
[3] 分析担当 データ分析
      ↓
🙋承認① 施策方向性
      ↓
🙋承認② KPI
      ↓
[4] 施策担当 セグメント・チャネル設計
[5] CR担当 クリエイティブ企画 （並行）
      ↓
🙋承認③ セグメント&クリエイティブ最終確認
      ↓
[6] セグメント作成（Audience Studio 等）
[7] 配信ツールでコンテンツ ファイナライズ
```

---

## ステップ1: 【PM】ヒアリング

### 聞くこと（1回のAskUserQuestionにまとめる）
1. 施策の目的
2. ターゲット仮説
3. 期待成果（定量）
4. 制約（期間・予算・NG）
5. 類似過去施策があれば参考情報

### 成果物
`projects/<project-id>/01_plan/brief.md` （PMブリーフ）

---

## ステップ2: 【PM】→【分析】指示書発行

### テンプレート
```
【PM】→【分析】
分析観点を以下にお願いします:

目的: <>
ターゲット仮説: <>
分析観点:
  1. 対象顧客の規模（セグメント候補ごとの人数試算）
  2. 対象顧客の特徴（年代・エリア・購買傾向）
  3. 類似過去施策の実績があれば参照
  4. KPI候補値の現状値

期限: 本日中
保存先: projects/<project-id>/01_plan/analysis.md
```

---

## ステップ3: 【分析】データ分析

- `reference/data-sources.md`（`related_skills.sql_guideline` が設定されていればそのSkillも）のガイドラインを厳守
- テーブル名・カラム名・売上ルールは `config/environment.yml` の値だけを使う。未記載のものは利用者に確認してから使う
- `tdx query` を実行する前に必ず **AskUserQuestion で承認を取る**
- クエリは `projects/<project-id>/01_plan/queries/` に保存
- 結果は `analysis.md` に表・考察とともに記録

### 必須アウトプット
- セグメント候補別の人数・平均LTV・平均注文回数
- 施策仮説の裏付け or 反証データ
- KPI現状値（開封率・CTR・CVR・1人あたり売上 の過去実績）

---

## 🙋 承認①: 施策方向性の確定

**AskUserQuestion** で以下を提示:

```
【PM】分析結果を踏まえ、以下の方向性を提案します。

方向性案A: <ターゲットX への 訴求Y>
  - 想定対象: 〇〇人
  - 期待効果: ...
  - 懸念: ...

方向性案B: <別案>
  ...

推奨: 案A

→ どの方向性で進めますか？
```

成果物: `projects/<project-id>/01_plan/direction.md` （承認済方向性を記録）

---

## 🙋 承認②: KPIの確定

**AskUserQuestion** で以下を提示:

```
【PM】Checkで施策の良し悪しを判定する指標を確定します。

主KPI候補:
  - 対象セグメントの購買率（配信後14日）: 目標 X%
  - 配信経由売上: 目標 ¥XXX

副KPI候補:
  - 開封率: 目標 X%
  - CTR: 目標 X%
  - LTV 増分: 目標 X%

→ この指標・目標値で確定しますか？
```

成果物: `projects/<project-id>/01_plan/kpi.md`

---

## ステップ4-5: 【施策】&【CR】並行作業

### 【施策】
- セグメント定義を `environment.yml` の `audience`（`related_skills.segment_builder` が設定されていればそのSkillも）に沿って作成
- 配信許諾・除外顧客・配信上限（`defaults.frequency_cap`）を条件に必ず含める
- チャネル・配信スケジュール設計
- CJO利用時は `related_skills.cjo`（既定 `cjo-journey-tips`）参照
- 成果物: `01_plan/segment_spec.md`

### 【CR】
- 訴求軸・コピー・ビジュアル仕様
- A/Bテスト設計
- 成果物: `01_plan/creative_spec.md`

**並行作業中は、PMが双方の整合性（セグメント特徴とコピーが噛み合っているか）をチェック**

---

## 🙋 承認③: セグメント&クリエイティブ最終確認

**AskUserQuestion** で以下を確認:

```
【PM】配信前の最終確認です。以下でセグメント作成・配信ツールに投入してよろしいですか？

セグメント: <概要>  詳細: segment_spec.md
クリエイティブ: <概要>  詳細: creative_spec.md
配信スケジュール: <日時>

→ 承認 / 修正 / 中止
```

---

## ステップ6: 【施策】セグメント作成

- `environment.yml` の `audience.tool` に従う
  - `audience_studio`: `audience.parent_segments` の Parent Segment を使用（用途が複数ある場合はどれを使うか確認）
  - `sql_table`: セグメントテーブルを作成するSQLを `01_plan/queries/` に保存し、承認後に実行
  - `other`: 利用者のツールでの作成手順を案内し、作成結果（名称・件数）を記録
- `related_skills.segment_builder` が設定されていればそのSkillを参照
- `tdx` コマンド実行時は必ず AskUserQuestion で承認
- 進行中の他プロジェクトとの顧客重複を確認（`reference/project-management.md` 6章）

## ステップ7: 【CR/施策】配信ツールでコンテンツ ファイナライズ

- 配信前チェックリスト（`personas/creative-planner.md`）を全項目クリア
- モバイル・PC表示確認
- テスト配信（自分宛）

---

## Phase終了時の処理

`project_state.json` を更新:
```json
{
  "current_phase": "do",
  "plan_completed_at": "<ISO8601>",
  "approvals": {
    "direction": {...},
    "kpi": {...},
    "final_check": {...}
  }
}
```

Phase 2 (Do) に進む準備完了を PM が宣言する。
