---
name: crm-check
description: CRM施策PDCAサイクルのCheckフェーズ（配信後の多角分析・KPI達成度判定・洞察抽出）を実行する。配信完了後、効果検証フェーズを単独起動したいとき用。「/crm-check」「施策の効果検証をしたい」などで発動する。
action: true
---

# /crm-check — Check フェーズ単独起動

このSkillは `crm-pdca` の Check フェーズを直接開始する。

## 動作
1. 対象プロジェクトを確認（AskUserQuestion）
2. `project_state.json` から配信実績情報と KPI を読み込む
3. 配信結果の基礎集計テーブル有無を `environment.yml` の `engage_analytics` で確認、未整備なら `engage_analytics.package_url` の導入を提案
4. `crm-pdca/phases/check.md` のステップに従って多角分析を実行
5. 完了後 `current_phase: "action"` に更新

## 前提
- 作業フォルダに `crm-pdca/config/environment.yml` があること（無ければ `crm-pdca/SKILL.md` の手順0に従いセットアップを案内）
- Do フェーズが完了し、配信から `defaults.check_wait_days`（既定3日）以上経過していること（開封・CTR データ揃い待ち）
- 開始時に 【分析】ペルソナで入る
- `reference/data-sources.md`（または `related_skills.sql_guideline`）のSQLガイドライン厳守
- tdx 実行時は必ず承認を取る

## 分析観点
A. 配信パフォーマンス (開封/CTR/エラー)
B. Web流入 (セッション/経路)
C. サイト内行動 (PV/滞在/カート)
D. 購買 (CV/CVR/売上/LTV増分)
E. セグメント横断・コントロール群比較

詳細フローは [`../crm-pdca/phases/check.md`](../crm-pdca/phases/check.md) を参照。
