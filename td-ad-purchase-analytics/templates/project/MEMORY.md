# Project memory

## 目的・合意
- プロジェクト名 / 担当 / 作成日
- 今回の問い、施策、獲得期間、購入観測終了、タイムゾーン
- 追加指標、分母、帰属モデル、未決事項

## 入力と品質
- 現在のTreasure Workアカウント識別情報（秘密値は書かない）
- Web DB.table / 実際のカラムマッピング / 保持開始 / 欠損
- Cookie / SDK session / window timeout / 会員ID / 実ログインor会員ID観測
- MAX(user_id)の型と順序 / 複数IDsession件数
- 注文正本・粒度・ID・金額・通貨・対象ステータス・取消返品
- 広告費の正本・粒度・カバレッジ / 内部ドメイン
- 前回成功時の入力min/max時刻 / 最古first-touch / 入力件数

## 設定ファイル
- `config/project.json` — 合意済みの正本
- `config/params.yml` — 検証スクリプトが生成するWorkflowパラメータ
- `queries/00_web.sql`, `00_orders_separate.sql`, `00_costs.sql` — 実テーブルadapter
- `dashboard_output/mapping.json` — 集計マートとUIの対応
- `dashboard_template/` — pinしたTDテンプレートとロゴ（SHA256も記録）

## 更新・公開履歴
|更新日時|attempt ID|観測終了|QA|完了テーブル|dashboard output|備考|
|---|---|---|---|---|---|---|

成功時だけこの表と `runs/latest_success.json` を更新する。失敗は `runs/<run_id>/` に理由を残し、前回成功を維持する。履歴保持の短縮、設定変更、帰属変更は特記する。

## 禁止する記録
APIキー、認証トークン、生の会員ID・Cookie、個人を含むURL、購入明細の生データをこのファイルや公開リポジトリに記録しない。

作成 Treasure Work
