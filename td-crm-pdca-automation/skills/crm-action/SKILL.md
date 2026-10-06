---
name: crm-action
description: CRM施策PDCAサイクルのActionフェーズ（Check結果を受けた継続/修正/中止の意思決定支援）を実行する。次サイクルの方針決定を単独起動したいとき用。「/crm-action」「次の施策方針を決めたい」などで発動する。
action: true
---

# /crm-action — Action フェーズ単独起動

このSkillは `crm-pdca` の Action フェーズを直接開始する。

## 動作
1. 対象プロジェクトを確認（AskUserQuestion）
2. `03_check/analysis_report.md` と `03_check/insights.md` を読み込む
3. `crm-pdca/phases/action.md` のステップに従って:
   - 【PM】総括
   - 【施策】&【CR】修正案 or 継続案
   - 🙋承認④ 次サイクル意思決定
4. 決定を `04_action/next_action.md` に記録
5. 継続/修正なら新サイクルの Plan へ、終了ならプロジェクトアーカイブ

## 前提
- 作業フォルダに `crm-pdca/config/environment.yml` があること（無ければ `crm-pdca/SKILL.md` の手順0に従いセットアップを案内）
- Check フェーズが完了していること
- 開始時に 【PM】ペルソナで入る
- 必ず AskUserQuestion で承認④ を取る

## 選択肢テンプレ
- A: 現状継続（セグメント拡大）
- B: 修正継続（具体修正点明示）
- C: 中止・ピボット
- D: プロジェクト完了（学び横展開）

詳細フローは [`../crm-pdca/phases/action.md`](../crm-pdca/phases/action.md) を参照。
