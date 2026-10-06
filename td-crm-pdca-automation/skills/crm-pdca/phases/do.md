# Phase 2: Do

目的: Planで確定した施策を実行する。

## ステップ全体像

```
[1] 配信直前の最終チェック
      ↓
[2] セグメントの最終確定
[3] 配信ツールで配信実行
      ↓
[4] 配信ログ記録
```

---

## ステップ1: 【施策/CR】配信直前の最終チェック

### チェックリスト
- [ ] セグメントサイズが想定通りか（セグメント作成ツールの最新件数確認）
- [ ] 除外対象（配信疲労・NG顧客・`business_rules.excluded_customer_condition`）が除外されているか
- [ ] 配信許諾のある顧客だけになっているか
- [ ] 配信上限（`defaults.frequency_cap`）を超える顧客がいないか
- [ ] クリエイティブのリンク切れ無し
- [ ] 差し込みフィールドのダミー値が残ってないか
- [ ] コントロール群設定
- [ ] 配信時刻・曜日が妥当か（`defaults.avoid_send_windows` を避ける）
- [ ] 法務チェック（`compliance.checks`）

### 問題発見時
PMがクライアントに即エスカレーション。配信を止めるか、修正して再承認を取る。

---

## ステップ2-3: 【施策】配信実行

### セグメントの最終確定
`environment.yml` の `audience` に従う（`related_skills.segment_builder` が設定されていれば参照）。`tdx` を使う場合は AskUserQuestion で事前承認。

### 配信ツールでの配信
`delivery.tools` に設定された配信ツールで実行する。
- Engage Studio: 設定済みの Workspace（`delivery.engage_workspace`）で配信
- CJO: ジャーニー配信の場合は CJO 側で起動（`related_skills.cjo` 参照）
- 外部ツール: 利用者が実行し、配信数・ジョブIDなどを共有してもらう

配信（外部送信）は取り消せないため、実行前に対象件数・チャネル・日時を示して必ず承認を取る。

### 配信実行の様子をPMが実況
```
【PM】配信を実行します。
  - 対象セグメント: <名前> (XX,XXX件)
  - 配信チャネル: メール
  - 配信ジョブID: <>
  - 配信開始: <timestamp>
```

---

## ステップ4: 【PM】配信ログ記録

成果物: `projects/<project-id>/02_do/delivery_log.md`

```markdown
# 配信実行ログ — <project-id>

## 配信#1
- 日時: 2026-10-15 10:00 JST
- チャネル: メール
- セグメント: dormant_180d_f1_202610
- 配信数: XX,XXX
- クリエイティブ: creative_A.html
- ジョブID: <>
- 配信者: <AI 施策担当 + 人間確認>
- 備考: 

## 配信#2
...
```

### スナップショット保存
`02_do/delivery_result/` に以下を保存:
- 配信直後の到達・配信エラー数（配信ツールのサマリ）
- 配信時点のセグメントメンバーリスト（可能なら）

---

## Phase終了時の処理

- `project_state.json` を更新 → `current_phase: "check"`
- Checkフェーズに進むタイミングは配信から **`defaults.check_wait_days`（既定3日）経過後**（開封・CTR 等のデータが揃うのを待つ）
- 遅延計測が必要な指標（LTV増分 等）は配信後 `defaults.ltv_followup_days`（既定30日）のタイミングで追加分析を予定

### 次フェーズへの引き継ぎ

PMが分析担当に Check 開始を指示:
```
【PM】→【分析】
配信完了しました。Check 分析をお願いします。

配信期間: 2026-10-15 〜 2026-10-25
基本集計: 配信後7日時点
深掘り分析: 配信後30日時点（別途依頼）
評価KPI: kpi.md 参照
保存先: projects/<project-id>/03_check/
```
