# ジャーニーの状態確認・効果確認

出典: td-tdx-journey（references/analyze.md, journey-table.md）。改修前の現状把握と、改修後の反映確認に使う。
ダッシュボードやアクションレポートまで作る依頼は、Studio の grid-dashboard / action-report 機能を併用する。

## 1. 確認コマンド（すべて読み取り）

```bash
tdx journey view "<journey>" --include-stats   # DB/テーブル、ステージ、ゴール、reentry
tdx journey versions "<journey>"               # バージョン一覧（latest / state）
tdx journey version view "<journey>" --version <N>
tdx journey activations "<journey>" --json > /tmp/acts.json
python3 scripts/latest_activations.py /tmp/acts.json      # 名前ごとの最新ID・重複
tdx journey columns "<journey>"                # 列 ↔ ステージ / ステップ対応
tdx journey stats "<journey>"                  # 累積KPI（entered, goal_achieved, exit_or_jump）
tdx journey traffic "<journey>" --from <90日前> --to <今日>   # Sankey（90日を超えると空）
```

## 2. ジャーニーテーブルの読み方

- DB `cdp_audience_<parent_segment_id>`、テーブル `journey_<journey_id>`。
- **スナップショット**: 実行のたびに全置換、全行同じ `time`、1行 = 1 `cdp_customer_id`。`time` で期間絞り込みをしない。
- 主キーは `cdp_customer_id`（`profile_id` ではない）。

| 列 | 意味 |
|---|---|
| `intime_journey` / `outtime_journey` | ジャーニー入場 / 退出 |
| `intime_goal` | ゴール到達 |
| `intime_stage_<N>` / `outtime_stage_<N>` | ステージN（0始まり）入退場 |
| `intime_stage_<N>_milestone` | マイルストーン到達 |
| `intime_stage_<N>_exit_<M>` | 退出条件M |
| `intime_stage_<N>_<step_uuid>` / `outtime_...` | ステップ入退場 |
| `branch_stage_<N>_<step_uuid>` | 選ばれた分岐 index |
| `variant_stage_<N>_<step_uuid>` | ABテスト variant（0=Control） |

現在ステージ = 後ろのステージから見て最初に `intime IS NOT NULL AND outtime IS NULL` のもの。
時刻は Unix 秒。日数 `(t2 - t1) / 86400.0`。割り算は `NULLIF(分母, 0)`。

```sql
SELECT
  COUNT(*) AS rows, COUNT(DISTINCT cdp_customer_id) AS customers, COUNT(DISTINCT time) AS snapshots,
  COUNT(intime_stage_0) AS entered_s0, COUNT(intime_goal) AS goal
FROM cdp_audience_<ps_id>.journey_<journey_id>
```

## 3. 累積 vs スナップショット

- `tdx journey stats` の `entered` / `exit_or_jump` / `goal_achieved` は**累積**（SQLでは出せない）。
- SQL は**現在**の状態のみ。`size` だけ両者一致。

## 4. 改修後の反映チェック（必須）

1. `tdx journey versions` で latest が想定のバージョン・state か
2. `tdx journey pull "<journey>"` した YAML と、push した YAML の差分が想定どおりか
3. `latest_activations.py` で各アクティベーションの接続先・`workspaceId`・`alwaysOnCampaignId`・カラム数が想定どおりか、古い重複IDが残っていないか
4. Console でフロー・分岐条件（特に `excluded`）・フォルダを目視
5. 配信を伴う場合は Console の Simulation Mode、`simulate_journeys` / `preview_journey` で確認
