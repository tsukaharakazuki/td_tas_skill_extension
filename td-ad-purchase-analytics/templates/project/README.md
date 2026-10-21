# 広告獲得・購買分析プロジェクト

最初に `MEMORY.md` の目的・制約と `config/project.json` の未確定値を埋めてください。このテンプレートはそのままでは実行できません。

## 更新順序
1. 現在の目的、元テーブルの保持範囲、前回成功runを読む。
2. Web/注文/広告費adapterを実際のschemaに合わせる。
3. `config/project.json` の合意内容を確認し、`configured=true` にする。
4. Skill付属の `validate_project.py <このprojectの絶対path> --compile-config` を実行する。
5. `.dig` timezoneと設定を揃え、ローカル検証、pushの対象確認・承認を行う。
6. Workflow run dry-runで範囲を説明し、明示承認後に実行する。
7. 同一attemptのQA/completeが成功した場合だけ、集約データでdashboardを再生成する。
8. 表示確認後にlocal最新へpromoteし、MEMORYの成功履歴を更新する。

run時の `-p` で設定を上書きしません。profile/siteを切り替えません。APIキー等は記録しません。外部通知・外部公開・スケジュール登録は別途承認が必要です。

## ファイル
- `ad_purchase_analytics.dig` — 全保持履歴再構築。scheduleなし。
- `queries/00_web.sql` — Web列マッピング。
- `queries/00_orders_separate.sql` — 別購買を使う場合だけ設定。
- `queries/00_costs.sql` — 広告費を使う場合だけ設定。
- `config/project.json` — 合意済み設定の正本。
- `config/params.yml` — compileで生成。直接編集せずJSONを更新。
- `dashboard_template/` — pinしたTDブランド原本。
- `dashboard_output/mapping.json` — このprojectのKPI・表・グラフ対応。
- `runs/` / `dashboard_output/runs/` — 成功・失敗のrun情報とHTML。
- `.digdagignore` — dashboardや取得データをWorkflow uploadから除く。使用CLIのdry-runで除外が反映されているか確認する。

詳細な指標契約・操作・dashboard bundleの形式は、導入元 `td-ad-purchase-analytics/references/` を参照してください。

作成 Treasure Work
