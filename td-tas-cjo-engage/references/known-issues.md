# 既知の挙動・落とし穴（DEMO 検証で更新する）

状態: ✅ 検証済み / 🔍 ソース確認のみ（tdx 2026.10.4 の CLI 本体） / ⚠️ 報告ベース（未検証） / ❓ 未確認
DEMO で確認したら状態と日付・tdx バージョンを更新し、関係する reference 本文も直す。

| # | 挙動 | 状態 | 対応（参照） |
|---|---|---|---|
| K-01 | REST API（PATCH/PUT）は不正な値・構造でも受け付けることがあり、ジャーニーが壊れる | ⚠️ 利用者報告 | 本番に直接当てない。テストジャーニーで先に実行・Console確認・GETバックアップ（journey-update-safety.md） |
| K-02 | エントリー条件を変えるとジャーニーのバージョンが上がり、旧バージョンでジャーニー内にいたユーザーがステージ途中で抜ける | ⚠️ 利用者報告 | 影響人数を出して明示承認、代替案を提示（journey-update-safety.md 3.） |
| K-03 | exit_criteria / milestone の変更でもバージョンが上がるか・途中ユーザーが抜けるか | ❓ | 未確認の間は K-02 と同じ扱い（tests D-1b） |
| K-04 | `tdx journey push` はフォルダ（YAML の置き場所）+ 名前で既存ジャーニーを照合。別フォルダ・別名だと新規作成 | 🔍 | pull した場所で編集。push 後 URL / versions を確認（journey-build.md Step 5） |
| K-05 | YAML の `folder:` は無効。フォルダはファイルの置き場所と `folder_id` で決まる | 🔍（cjo-journey-tips の報告と整合） | フォルダ移動は Console |
| K-06 | push のアクティベーションは名前で照合して更新。接続先変更で新IDになり、Console が旧IDを参照し続けることがある | 🔍 + ⚠️ | `latest_activations.py` で最大IDを確認、必要なら API PATCH |
| K-07 | `tdx journey activations` が旧バージョンの情報を返すことがある / push が 0 changed でも実態と乖離 | ⚠️ | API GET と Console で実態確認 |
| K-08 | YAML のアクティベーション列は「列名 + visibility」のみ。列名変更・ストリングビルダーは API のみ | 🔍 | activation-engage.md 5. |
| K-09 | 決定分岐の `excluded: true` が反映されないことがある | ⚠️ | push 後に pull / Console で確認、だめならルールで表現（segment-rules.md 7.） |
| K-10 | 一覧・entities 読み取りでセグメントの rule が空で返り、書き戻すとルールが消える | ⚠️（td-tdx-segment） | raw API でセグメントを書き戻さない |
| K-11 | `ref:` はジャーニー型セグメント（kind=3）だけ参照可能 | ⚠️（td-tdx-journey） | 新規は埋め込みセグメント |
| K-12 | AOC は tdx 2026.10 で pull / push / validate に対応（テンプレート・sender_id・UTM を YAML で） | 🔍 | engage-email.md 3.。古い tdx では Console 設定 |
| K-13 | キャンペーン / AOC の送信者は `email.sender_id`（旧資料の `connector.email_sender_id` は誤り） | 🔍 | engage-email.md |
| K-14 | Engage 未契約を示す専用エラーは CLI に無い | 🔍 | 複数シグナルで判定、403 だけで未契約と断定しない（engage-setup.md 1.） |
| K-15 | 送信ドメイン・送信者・Engage コネクションの作成コマンドは無い（一覧・割当のみ） | 🔍 | Console 作業として案内 |
| K-16 | Engage V1 の connector_config キー: campaign_type / campaign_model / workspace_id / always_on_campaign_id / list_campaign_id / campaign_id / json_columns / batch_size / thread_count | 🔍（`tdx connection schema treasure_engage_v1`） | activation-engage.md 3. |
| K-17 | `tdx journey traffic` は90日を超える範囲を指定すると空 | ⚠️（td-tdx-journey） | 90日以内で取得 |
| K-18 | 未契約・権限不足時の実際のエラーメッセージ | ❓ | DEMO で記録 |
| K-19 | テストジャーニーで本番と同名のアクティベーションを使っても本番側は変わらないか | ❓ | 確認まで push 後に本番の activations も取得（journey-update-safety.md 4.） |

## 更新履歴

| 日付 | 内容 |
|---|---|
| 2026-11-02 | 初版（cjo-journey-tips・td-skills-compact・tdx 2026.10.4 ソース調査・利用者報告から作成） |
