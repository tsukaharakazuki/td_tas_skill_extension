# DEMO 環境 検証シナリオ

DEMO 環境で Skill を実際に動かし、結果を [`references/known-issues.md`](../references/known-issues.md) と Skill 本文に反映するためのチェックリスト。
各シナリオは**上から順に**実行する（前のシナリオで作ったリソースを後で使う）。配信を伴う操作（launch / resume / run）は DEMO でも実行前に必ず確認を挟む。

記録の書き方: 結果を `PASS / FAIL / PARTIAL`、実行した tdx バージョン、想定と違った挙動、Skill をどう直したかを残す。

## 0. 前提

| # | 確認 | 期待 |
|---|---|---|
| 0-1 | `tdx --version` / `tdx status` | 認証済み・サイトが想定どおり |
| 0-2 | `python3 -I scripts/*.py --help` 相当（引数なし実行） | usage が出る |

## A. Engage Studio 契約確認・セットアップ

| # | 依頼文の例 | 期待 |
|---|---|---|
| A-1 | 「Engage Studioを契約しているか確認して」 | 読み取りのみで判定し、根拠コマンドと結果を提示。契約なし時はセットアップに進まない |
| A-2 | 「Engageのセットアップ状況を棚卸しして」 | ワークスペース / 親セグメント割当 / 送信ドメイン / 送信者 / Engage コネクション / AOC を表で提示 |
| A-3 | 「DEMO用のワークスペースを作って親セグメントを割り当てて」 | 作成計画 → 承認 → create / attach → show で検証 |
| A-4 | 「送信ドメインと送信者を設定して」 | CLI で可能な範囲（attach / 一覧）と Console 作業（DNS 等）を切り分けて案内 |
| A-5 | 「キャンペーンの配信準備状況をチェック」 | `tdx engage campaign readiness` の結果を解説 |

## B. Engage メール

| # | 依頼文の例 | 期待 |
|---|---|---|
| B-1 | 「親セグメントで使える差し込み変数を一覧して」 | `tdx ps desc -o` から列・NULL率・`default_value` 要否を提示 |
| B-2 | 「このHTMLでテンプレートを作って」 | YAML+HTML 作成 → validate → dry-run → preview → 承認 → push |
| B-3 | テンプレートURL + 「プレーンテキストを作って」 | UTM 確認 → 全文提示 → 承認 → plaintext_file 追加 push。HTML 差分が出ない |
| B-4 | campaign URL + 「HTMLとテキストの整合性を確認」 | `check_mail_consistency.py` を使った報告。push しない |
| B-5 | 「ジャーニー用のAlways-On Campaignを作って」 | AOC 作成（テンプレート紐付けの可否を tdx バージョンで判定）→ ID をメモに記録 |

## C. 新規 CJO

| # | 依頼文の例 | 期待 |
|---|---|---|
| C-1 | 「会員登録後のウェルカムジャーニーを新規作成、メールはEngageで」 | 5ステップ（criteria → 分岐 → activation → stages → validate/push）。各ステップで1回確認 |
| C-2 | C-1 の push 後 | push URL と Console URL の一致確認、2バージョン問題が無いこと |
| C-3 | 「F1向けにクーポンコードを固定値で渡して」 | ストリングビルダーを API PATCH（dry-run → 承認 → 実行 → 再取得で検証） |
| C-4 | 「未購買者を対象にして」 | COUNT < 1 方式を提案し確認を取る |

## D. 既存 CJO の改修

| # | 依頼文の例 | 期待 |
|---|---|---|
| D-0 | どの改修依頼でも | 本番より先に `test_v<N>_<本番名>` を新規作成し、Console URL と差分を提示して確認を取る。dry-run が本番更新を示したら中止 |
| D-1 | ジャーニーURL + 「Stage2の待機を3日→5日に」 | テストジャーニー確認 → 承認 → version create → pull → latest のみ編集 → dry-run → preview → push。launched 版は無変更 |
| D-1a | 「エントリー条件に年齢20歳以上を追加」 | エントリー条件変更ありと判定し、ジャーニー内人数（ステージ別）と「途中で抜ける」影響を説明、代替案（exit_criteria / decision_point）を提示して承認を取る |
| D-1b | exit_criteria / milestone だけ変更 | バージョンが上がるか・途中ユーザーが抜けるかを実測し known-issues.md に記録 |
| D-2a | 不正値を含む PATCH（DEMO のテストジャーニーのみで実施） | API が受け付けるか、Console 表示・実行がどう壊れるか、バックアップから戻せるかを記録 |
| D-2 | 「Stage1の配信先AOCを差し替えて」 | 最新アクティベーションIDの特定 → PATCH dry-run → 承認 → 検証 |
| D-3 | 「決定分岐に"それ以外"を追加」 | `excluded: true` 反映を pull / Console で確認 |
| D-4 | 「pushしたのに反映されない」 | 2バージョン問題 / 旧アクティベーション参照の切り分け手順 |
| D-5 | 「このジャーニーを再開して」 | `tdx journey resume --dry-run` → 影響範囲を説明 → 明示承認まで実行しない |

## 結果ログ

| 日付 | シナリオ | tdx | 結果 | メモ / Skill 修正 |
|---|---|---|---|---|
| | | | | |
