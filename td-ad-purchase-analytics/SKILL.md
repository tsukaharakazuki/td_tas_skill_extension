---
name: td-ad-purchase-analytics
description: Use when the user wants to analyze or build long-term tracking from ad-driven new Cookie acquisition to login and purchases using Treasure Data JS SDK web logs, including 広告獲得分析, 広告から購買まで追跡, 新規Cookie獲得, 会員化分析, 購買転換, 長期ROAS, 購入前7日間の流入, td-ad-purchase-analytics, or a GitHub URL to this skill. Interview the user, build project-specific TD Digdag workflows and canonical marts, remember decisions in project MEMORY.md, and update a TD-branded HTML dashboard only after a successful validated workflow. Supports existing SDK session IDs or TD_SESSIONIZE_WINDOW, session MAX member enrichment, GA4 ecommerce web-only purchases, optional member-linked purchase tables and ad spend. Does not activate campaigns or publish externally without approval.
---

# 広告獲得・購買転換トラッキング

`td_client_id`を軸に、保持Webログでの初回獲得 → 会員ID観測 → その後の購買を追跡する。顧客ごとの設定・Workflow・ダッシュボードを `Project/<project_name>/` にまとめ、初回構築と継続更新の両方を扱う。

## 最初にすること
1. 初回構築・更新・仕様相談のどれかを見極める。更新なら既存 `Project/MEMORY.md` と対象projectの `MEMORY.md`、config、最新成功runを先に読む。
2. 集計目的・対象施策・獲得期間・購入観測期間・Web DB.table・project名を確認する。既知情報を再質問しない。詳細は [hearing.md](references/hearing.md)。
3. 必須Webログに `td_client_id` があることを確認する。会員ID・session ID・UTM/URL/referrer・ecommerce・別購買・広告費・追加集計要望を調べる。
4. TD操作前に `tdx-skills:tdx-basic`、SQL実装前に `sql-skills:trino`、WF作成時に `workflow-skills:digdag` を読む。未導入ならバンドル仕様と公式資料を確認し、CLI helpで操作を検証する。
5. [analytics-contract.md](references/analytics-contract.md) を読んで指標・粒度・帰属を固定する。未確認のテーブル・カラムは推測して実行しない。

## プロジェクトを初期化する
Skillのインストール先を `<skill_dir>` として、次を使う。

```bash
python3 -I <skill_dir>/scripts/init_project.py --workspace <workspace> --name <project_name> --dry-run
python3 -I <skill_dir>/scripts/init_project.py --workspace <workspace> --name <project_name>
```

- `Project/` がなければ作り、指定projectを作る。既存projectは上書きしない。初期化のやり直しで過去設定を消さない。
- project内の `config/project.json` を設定の正本とする。合意・列マッピング・制約・追加要望・成功run履歴はprojectの `MEMORY.md` に記録する。
- `Project/MEMORY.md` はprojectへの索引にする。個人グローバルMEMORYに顧客データを保存しない。
- APIキー・トークン・Cookie・会員IDの生値をconfig/MEMORY/Gitへ保存しない。

## Web・セッション・会員を整える
1. 全保持Webログから初回観測を作る。**レポート獲得期間で先に原本を絞らない**。保持開始・欠損・Cookie期限を記録する。
2. 有効なSDK session IDがあればcookieと組み合わせて使う。IDがない場合は次で分割し、cookie内でsession_numberを1から付ける。

```sql
TD_SESSIONIZE_WINDOW(event_time, 1800)
  OVER (PARTITION BY td_client_id ORDER BY event_time)
```

3. timeoutの既定は30分。SDKの欠損・再利用を調べ、行ごとのSDK/推測IDの安易な混在は避ける。window関数の一時IDは一度materializeし、公開キーはcookieと境界から作る。
4. sessionごとに `MAX(user_id)`（正規化後の文字列）を採用し、途中ログインも補完する。複数IDでもMAXで処理し、分配・除外へ勝手に変えない。競合件数はQAに残す。
5. 補完会員IDとは別に、その選ばれたIDを実際に観測した時刻を保持する。注文以前の観測だけを「ログイン後購買」の根拠にする。等秒で順序不明な注文は既定で含めない。
6. 実ログインイベントがない場合は「会員ID観測」と表記する。Cookie数を人物UUと呼ばない。

## 流入モードを作る
- **landing** — session先頭の流入1件。初回sessionのlandingをCookieの獲得元として固定する。
- **session_inflow** — landingとsession中の外部/UTM流入を保持し、session×source群で関連分析する。初回session内の流入はすべて新規、2回目以降のsessionは再訪とする。
- 内部・決済ドメインの通常遷移は新しい外部流入にしない。UTM・外部referrerの優先規則を記録する。
- session_inflowは複数施策に同じCookieが出る。施策別Cookie・関連注文・関連売上を単純合算しない。全体KPIはlandingの排他的集計から出す。
- 時間条件付き分析のため、流入の発生時刻を保持する。session-sourceの最初の時刻だけに潰してからlookback結合しない。

## 購買を整え、集計する
1. `purchase_mode` をweb / separateから選ぶ。別購買が正本ならseparateを推奨し、GA4/Web購買と売上を二重計上しない。
2. webではGA4 dataLayerのpurchase/transaction_id/value/currency、または完了URLと注文IDを確認する。注文IDのない完了URLは購入シグナルであり、注文数・売上・ROASを確定しない。
3. separateでは会員ID・注文ID・注文日時・金額・更新順・取消返品を確認し、1注文1行へ正規化する。明細に反復する注文合計をSUMしない。
4. ログイン後購買は、注文より前に実際に会員観測した候補へ結ぶ。複数Cookie候補は**全履歴から注文以前の直近会員観測Cookieを1つ**選ぶ。cohort絞り込みは選択後に行う。
5. 基本指標を出す — 獲得Cookie数、会員ID観測Cookie数/率、ログイン後購買Cookie数、注文数、購買金額、購買転換率。
6. 別モデルとして、会員IDで購入前lookback（既定7×24時間）の流入を結合し、last-touchを作る。初回獲得元の売上に足さない。
7. 広告費を入力する場合は日付・施策・通貨の粒度を揃え、獲得コホートROASを出す。費用未入力/0円・金額不明・通貨不一致はNULL。費用だけの施策も残す。
8. 商品別・再購入・7/30/90日等の追加要望は確認し、式・粒度・観測成熟度を契約に加えてからSQL/QA/mappingを拡張する。未実装の追加指標を「対応済み」と言わない。

## Workflowを作成・更新する
- `templates/project/queries/00_web.sql` 等のadapterを実データへ対応させる。他のSQLはcanonical列を参照する。初期状態は `configured=false` で実行不能。
- 確認後に `configured=true` とし、`python3 -I <skill_dir>/scripts/validate_project.py <project> --compile-config` でparamsを生成する。
- [operations.md](references/operations.md) に従う。v1は全保持履歴の再構築であり、増分更新を実装済みと説明しない。
- 出力はattempt別のテーブル。QA成功後にだけcompleteを作る。失敗runをdashboardへ反映せず、前回成功を維持する。
- 現アカウントのprofile/siteを切り替えない。実行時 `-p` で挙動を変えず、configに反映して検証する。
- push/既存WFの置換は対象と差分を説明して承認を得る。**runは必ず `--dry-run` → 規模・作用の説明 → 明示承認 → 実行**。
- 既定にschedule・mail・http・activationは含めない。定期実行・外部共有は別途承認する。

## 成功後にdashboardを更新する
1. 同一attemptのcompleteとQAを確認し、cohortと補助分析を集約JSONへ取り出す。40行等の取得上限で切れていないか行数を照合する。
2. [dashboard.md](references/dashboard.md) を読み、同梱の `dashboard_template/SKILL.md` とHTMLを使う。TDロゴ、:root、フォント、フッターを保持する。
3. projectの `dashboard_output/mapping.json` にユーザー要望を反映する。任意の比率を平均せず、分子/分母から再計算する。
4. `render_dashboard.py --project <project> --data <bundle>` でrun別HTMLを生成する。データNULLを0と見せず、観測終了・Cookieの限界・補助指標の非加算性を表示する。
5. desktopと390pxで表示確認し、必要なら修正する。local最新への更新は同じコマンドに `--promote` を付ける。デモはpromoteしない。
6. `dashboard_output/` にHTML、mapping、取得JSONの参照を保ち、project MEMORYの成功履歴を更新する。
7. ファイルはopen_fileで表示する。外部URL公開・Driveアップロード・メール送信は別途承認を得る。

## GitHub URLで配布・読込する場合
このフォルダ全体をリポジトリへ配置する。URLを受けたらSKILL.mdと参照先・scripts・templatesを同じcommitで読み、別の空フォルダへ取得してレビューする。取得コードを未読で実行しない。Skillの読込は顧客データ送信やWorkflow実行への承認ではない。

GitHubへのpush/PRやmarketplace登録は利用者の明示依頼後に行う。同梱 `marketplace-entry.json` は登録用の例であり、自動登録ではない。

## 応答形式
- 今回の目的・project
- 採用した入力、session/会員/注文/帰属の定義
- 作成・更新したファイルとマート
- 検証結果（ローカル検証 / TD実行検証を区別）
- dashboardの場所・最終成功run・制約・次の確認事項

## 例
**入力**「春キャンペーンで初めて来たCookieが、3か月でどれだけ買ったか。注文テーブルもある」
**動作** 獲得日と観測期限・正本を確認 → 全保持Webから初回を判定 → separate注文を会員IDと過去の会員観測で結合 → landingコホート集計と購入前7日last-touchを別々に作る。90日未成熟cohortは比較から除外するか明示する。

**入力**「前回の広告分析を更新して」
**動作** 既存MEMORY/config/成功runを読む → 保持期間・設定差分を確認 → validate、dry-run、承認後WF実行 → QA/complete確認 → 同一runのdashboard更新。失敗なら前回成功を維持する。

作成 Treasure Work
