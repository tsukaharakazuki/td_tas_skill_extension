---
name: crm-plan
description: CRM施策PDCAサイクルのPlanフェーズ（施策目的ヒアリング・分析・方向性決定・セグメント&クリエイティブ設計）を実行する。/crm-pdca の Plan のみを直接起動したいとき用。「/crm-plan」「CRM施策の企画を始めたい」などで発動する。
action: true
---

# /crm-plan — Plan フェーズ単独起動

このSkillは `crm-pdca` の Plan フェーズを直接開始する。

## 動作
1. 対象プロジェクトを確認（AskUserQuestion: 新規 / 既存継続）
2. プロジェクト未作成なら `projects/<project-id>/` と `project_state.json` を初期化
3. `crm-pdca/phases/plan.md` のステップに従って進行
4. 完了後 `current_phase: "do"` に更新

## 前提
- 作業フォルダに `crm-pdca/config/environment.yml` があること（無ければ `crm-pdca/SKILL.md` の手順0に従いセットアップを案内）
- Parent Skill: `crm-pdca`（`SKILL.md`、`personas/*.md`、`templates/*` を参照）
- 開始時に PM【PM】ペルソナで入る
- 承認ポイント①②③ は必ず AskUserQuestion で取る
- tdx 実行時は必ず承認を取る

詳細フローは [`../crm-pdca/phases/plan.md`](../crm-pdca/phases/plan.md) を参照。
