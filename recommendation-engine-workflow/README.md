# Recommendation Engine Workflow

Treasure AI向けの汎用商品レコメンドWorkflowサンプルと、クライアントごとの最終実装を支援するTreasure AI Studio Skillです。

## Contents

- `recommendation-engine/` — 親Workflow、15種類の候補生成ロジック、最終統合Workflow、Hive SQL、Python Custom Script
- `SKILL.md` — 実顧客向けにテーブル・カラム・ロジック・重みを設定し、検証・デプロイするためのSkill
- `docs/index.html` — 各ロジックの詳細、使い分け、業界別活用ポイントをまとめたHTMLガイド
- `docs/treasure-ai-logo-white.png` — GitHub Pagesで利用するロゴアセット

## Workflow architecture

```text
recommendation-engine.dig
  ├─ enabled logics/*.dig
  │    ├─ rule-based candidates
  │    ├─ collaborative filtering
  │    ├─ attribute / RFM
  │    ├─ Python ML template
  │    ├─ Matrix Factorization
  │    ├─ seasonality
  │    └─ bandit template
  ├─ reco_all_candidates
  └─ final/final_output.dig
       └─ reco_final_output
```

## Key configuration

Client-specific settings are centralized in:

```text
recommendation-engine/config/params.yml
```

Configure:

- Source database/table names and columns
- `enabled` per recommendation logic
- Output key: `member_id`, `cookie`, or `td_client_id`
- Per-logic `top_n` and lookback period
- Final weights and diversity limits
- Stock, sale-status, and recent-purchase exclusions

The sample uses Hive SQL. The user-based collaborative filtering logic uses Python Custom Script and Matrix Factorization with Surprise SVD.

## Before deployment

1. Replace all dummy source tables and column mappings.
2. Confirm timestamp units and event-type values.
3. Confirm ID stitching between member ID and cookie/`td_client_id`.
4. Keep ML and bandit logic disabled until sufficient training or impression data exists.
5. Validate the Workflow and test candidate counts, null keys, exclusions, and final top-N.
6. Push or run only after explicit approval in the target TD account.

## HTML guide

The documentation is intended for non-engineering stakeholders and explains each logic using:

- What data it looks at
- What products it recommends
- When it should be used
- A concrete business example

GitHub Pages URL after enabling Pages for this repository:

```text
https://tsukaharakazuki.github.io/td_tas_skill_extension/recommendation-engine-workflow/
```
