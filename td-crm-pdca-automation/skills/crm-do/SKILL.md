---
name: crm-do
description: CRM施策PDCAサイクルのDoフェーズ（セグメント・配信ツールでの配信実行と配信ログ記録）を実行する。Plan完了後の配信実行フェーズを単独起動したいとき用。「/crm-do」「施策を配信したい」などで発動する。
action: true
---

# /crm-do — Do フェーズ単独起動

このSkillは `crm-pdca` の Do フェーズを直接開始する。

## 動作
1. 対象プロジェクトを確認（AskUserQuestion）
2. `project_state.json` が `current_phase: "do"` 相当か確認
3. `crm-pdca/phases/do.md` のステップに従って進行
4. 完了後 `current_phase: "check"` に更新

## 前提
- 作業フォルダに `crm-pdca/config/environment.yml` があること（無ければ `crm-pdca/SKILL.md` の手順0に従いセットアップを案内）
- Plan フェーズが完了していること（承認①②③済）
- 開始時に 【施策】ペルソナで入る（配信直前チェック以降）
- 配信直前チェックリストを完全クリアすること
- tdx 実行時は必ず承認を取る

詳細フローは [`../crm-pdca/phases/do.md`](../crm-pdca/phases/do.md) を参照。
