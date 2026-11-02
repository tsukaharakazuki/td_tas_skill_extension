# ジャーニー YAML 検証・フロー制御ルール

出典: td-tdx-validate-journey / td-tdx-journey。

```bash
tdx journey validate path/to/journey.yml   # ローカル（オフライン）
tdx journey push path/to/journey.yml --dry-run   # API 側の検証と差分
```

## 1. 必須構造

```yaml
type: journey
name: Journey Name
reentry: no_reentry        # no_reentry | reentry_unless_goal_achieved | reentry_always
segments: { ... }          # 埋め込みセグメント（キー → rule）
activations: { ... }       # キー → activation 定義（マップ。リストではない）
journeys:
  - state: draft
    goal:                  # 推奨（無いと MISSING_GOAL 警告）
      name: Goal Name
      segment: goal-segment
    stages:
      - name: Stage Name
        entry_criteria: { name: Entry, segment: entry-segment }   # 必須
        exit_criteria:  [ { name: Exit, segment: exit-segment } ] # 推奨
        milestone: { name: Milestone, segment: ms-segment }       # 最終ステージ以外は必須
        steps: [ ... ]     # 2ステップ以上（4以上推奨）
```

上限: ステージ8（ローカル検査）、イベント120/ジャーニー・70/ステージ、バージョン30（API）。

## 2. ステップ種別

| type | `with` | 注意 |
|---|---|---|
| `wait` | `duration`+`unit` / `condition` / `wait_until` | 条件待ちは**トップレベル `next:` なし**（`condition` 内に書く）。`days_of_week` も可 |
| `activation` | `activation: <キー>` | `activations:` に定義されたキー |
| `decision_point` | `branches[]` | 各ブランチに `segment` + `next`、catch-all は `excluded: true` |
| `ab_test` | `variants[]` | `percentage` 合計100 |
| `merge` | なし | 複数経路が合流する箇所に必須 |
| `jump` | `target: {journey, stage}` | `next:` なし。直前の wait 不要 |
| `end` | なし | `next` / `with` を書かない |

`next:` はステップ直下（`with:` の中ではない）。値は**ステップ名そのもの**（スラッグ化しない）。

```yaml
- type: wait
  name: Wait 7 Days
  next: Next Step
  with: { duration: 7, unit: day }            # day | week

- type: wait
  name: Wait for Purchase
  with:
    condition:
      segment: made-purchase
      next: Thank You Path
      timeout: { duration: 14, unit: day, next: Timeout Path }
```

## 3. エラーコード

| Code | 内容 |
|---|---|
| `MISSING_NAME` / `MISSING_STAGES` | name / stages が無い |
| `MISSING_GOAL` (warn) | goal 無し |
| `DUPLICATE_LATEST` | `latest: true` が複数 |
| `TOO_MANY_STAGES` | 8超 |
| `MISSING_ENTRY_CRITERIA` | entry_criteria 無し |
| `MISSING_MILESTONE` | 最終以外で milestone 無し |
| `MISSING_EXIT_CRITERIA` (warn) | exit_criteria 無し |
| `INSUFFICIENT_STEPS` / `FEW_STEPS` (warn) | 0-1 / 2-3 ステップ |
| `DUPLICATE_STEP_NAME` | ステップ名重複 |
| `INVALID_NEXT_REFERENCE` | `next` 先が存在しない |
| `MISSING_WAIT_PARAMS` | wait のパラメータ不足 |
| `MISSING_SEGMENT_REFERENCE` | 条件待ち・分岐に segment 無し |
| `MISSING_ACTIVATION_REF` | `with.activation` 無し |
| `MISSING_CONDITIONS` | 分岐・ABテストの中身無し |
| `INVALID_AB_TEST_PERCENTAGES` | 合計≠100 |
| `INVALID_JUMP_TARGET` | target.journey / stage 不足 |
| `END_STEP_HAS_NEXT_OR_WITH` | end に next / with |
| `MISSING_END_STEP` | end 無し |
| `CONVERGENCE_WITHOUT_MERGE` | merge 以外へ合流 |
| `SINGLE_INPUT_MERGE` (warn) | 入力1本の merge |
| `MERGE_TO_MERGE_CHAIN` | merge → merge |
| `BRANCH_DIRECTLY_TO_MERGE` | 分岐から直接 merge |
| `JOURNEY_SCHEMA_ERROR` / `ACTIVATION_SCHEMA_ERROR` | 型・必須・enum 違反 |
| `MISSING_ACTIVATION_DEFINITION` | activations にキーが無い |
| `UNUSED_EMBEDDED_SEGMENT` (warn) | 使われていない埋め込みセグメント |

### validate では検出されず API が拒否するもの

- 分岐（decision_point / ab_test / 条件待ち）の各経路は merge 前に**アクティベーションを1つ以上**持つ。
- **アクティベーションの後には必ず wait**。activation → merge の場合は merge の後に wait を置く。

## 4. 設計ルール（validator 外）

- 条件待ちの2経路が同じ処理なら duration wait にする。
- 分岐はフラットに。入れ子の内側分岐は外側に戻る前に merge。
- 頻度制御: アクティベーション間に wait、同一チャネル1日1通まで。
- 同意・抑止: opt-in は entry_criteria、配信停止・直近購入者などは exit_criteria。
- reentry: 単発は `no_reentry`、継続施策は `reentry_unless_goal_achieved`、繰り返しトリガーは `reentry_always`。

## 5. フロースケッチ（ステップを書く前に必ずコメントで書く）

```yaml
# Flow: Send Welcome → Wait 3 Days → Decision(Opened / Not Opened)
#       Opened     → Send Follow Up → Merge → Wait 1 Day → End
#       Not Opened → Send Reminder  → Merge
```

```yaml
- type: decision_point
  name: Email Open Check
  with:
    branches:
      - name: Opened
        segment: email_engaged
        next: Send Follow Up
      - name: Not Opened
        excluded: true
        next: Send Reminder
- type: activation
  name: Send Follow Up
  next: Merge Welcome
  with: { activation: follow-up-email }
- type: activation
  name: Send Reminder
  next: Merge Welcome
  with: { activation: reminder-email }
- type: merge
  name: Merge Welcome
  next: Wait After Welcome
- type: wait
  name: Wait After Welcome
  next: End Stage 1
  with: { duration: 1, unit: day }
- type: end
  name: End Stage 1
```

## 6. セグメント参照

- **埋め込み（推奨）**: `segment: my-segment`（`segments:` に定義）。新規は必ずこれ。
- **外部参照**: `segment: ref:Segment Name` は**ジャーニー型セグメント（kind=3、他ジャーニーの push で作られたもの）だけ**。`tdx sg push` で作った通常の子セグメントを `ref:` で参照すると ID は解決されても API に拒否される。
- 迷ったら埋め込み。他ジャーニーのロジックを再利用したいときは、そのジャーニーを pull してルールをコピーする。
- ゴール到達時に別ジャーニーへ: `goal.target: {journey: ..., stage: ...}`。
