# 集計契約 v1

## 識別と時間
- 主キーは `td_client_id`。人・世帯・クロスデバイスUUと呼ばない。会員IDは補助キー。
- `time` / `event_time` はepoch秒、全ウィンドウは `[start,end)`、ログ・注文とも `event_time < session_unixtime`。
- 初回は全保持ログを再構築する。v1は更新時も全履歴再構築。入力保持期間が短縮されると初回日時も変わるため、前回のmin時刻との比較が必要。履歴が失われた場合は更新を止め、first-touch台帳の永続化・過去履歴復旧を別設計する。
- 「新規」は**保持ログでの初回観測Cookie**。真の新規顧客とは区別する。レポート獲得期間で原本を先に絞らない。
- 獲得期間と購入観測期間を分離する。獲得後の注文は獲得期間終了後でも観測終了まで追う。

## セッション
SDK方式では `(cookie,sdk_session_id)`、window方式では次を使用する。

```sql
TD_SESSIONIZE_WINDOW(event_time, 1800)
  OVER (PARTITION BY td_client_id ORDER BY event_time)
```

関数の戻り値は内部グループキーとして1回materializeして使う。永続キーとして戻り値の再実行安定性を仮定しない。window方式の公開session_keyはcookieとsession_startから作る。SDK方式はcookieとSDK IDを連結する。session_numberはcookie内のsession_start順（同時刻はキー順）で1始まり。

公式 https://docs.treasure.ai/products/customer-data-platform/data-workbench/queries/sql-reference/td_trino_function_reference#td_sessionize_window

timeoutの境界一致（ちょうど1800秒）は実エンジンで確認する。資料から `>` / `>=` を推定しない。入力はepoch秒に統一する。同一秒内の順序は安定したevent_keyで決める。イベントIDがなければcanonical列からハッシュを作り、同一秒の実際の順序は分からない旨を記す。

## セッション内会員補完とログイン
session_member_id=`MAX(NULLIF(TRIM(member_id),''))`。同一セッションに複数IDがあってもMAXを採用する。別ルールへ黙って変更しない。`member_id_count>1` は品質指標として残す。

補完IDと**実際にID／ログインを観測した時刻**を分離する。会員観測テーブルには、セッションで選ばれたIDに一致し `is_login=true` の生イベントだけを残す。セッションの先頭へ会員IDを補完してもログイン時刻まで遡及しない。v1のログイン後購買は `member_observed_time < order_time` の厳密な前後関係を要求する。同一秒で順序が不明な注文は対象外とし、必要なら信頼できるイベント順序を追加して再設計する。

既存のID付イベントを `is_login=true` とした場合は「ログイン回数」ではなく「会員ID観測Cookie数」と表示する。ログイン成功イベントがある場合だけ実ログインと呼ぶ。

## 流入モード
UTMを優先し、なければ外部referrerのhostから `referral`、いずれもなければ `(direct)/(none)`。内部・決済ドメインの通常遷移を流入にしない。クロスドメイン・アプリ復帰・自社UTMの扱いを確認する。

|モード|粒度|新規判定|加算性|
|---|---|---|---|
|landing|sessionごとに先頭イベントの流入が1件|session_number=1|初回獲得Cookie・注文・売上はモード内で排他的|
|session_inflow|session×source/medium/campaign/content/term の最初の流入。landingも含む|初回sessionに含まれる全流入が新規|同じcookieが複数施策へ出る補助指標。施策行を合計しない|

初回sessionでA→Bならlanding=A、新規session_inflow=AとB。再訪sessionでCならCは再訪。更新で新しい流入に初回獲得元を書き換えない。

## 注文と単一Cookie帰属
1. web / separate のどちらか一方を正本として選ぶ。同じ注文の両方を合算しない。
2. canonical注文は単一通貨・`order_id`ごと1件。注文IDは正本内で全期間ユニークであることを確認する。店舗等で重複する場合adapterで名前空間を付ける。
3. `order_time` は取引日時であり、スナップショット更新日時ではない。最新更新の注文を採用する。重複スナップショット・再読み込みを除外する。注文更新の時系列、同順位の競合、取消・返品を調査する。
4. Web購入は同じcookieで注文以前の会員観測がある場合だけログイン後購買にする。注文にmember_idがあれば一致が必要。separate購入はmember_idで結ぶ。
5. 別購買が複数Cookieへ結びつく場合、全履歴の候補から**注文以前の直近会員観測Cookie**に1注文を1回だけ割り当てる。同時刻はcookie文字列順で決定する。このモデルを明記し、選択前に獲得期間でcookie候補を絞らない。
6. 帰属不能注文は捨てずに未帰属件数としてQAに記録する。Cookie単位の初回流入元へ紐づいた売上は、人物レベルの因果効果ではない。
7. 商品別などで複数行にする場合、注文全額を各商品へ付けない。粒度を変えた売上配賦を設計する。

## 購入前lookback
`[order_time - lookback_days*86400, order_time)` の流入を対象とする。デフォルト7日。会員IDで結合し、sessionのMAX補完を使うが、その会員を注文以前に実際に観測しているsessionに限る。最も新しい流入1件をlast-touchとして採用する。cohortのfirst-touchと別テーブル・別ラベルで示し、売上を足し合わせない。全候補を表示する補助分析は多対多であることを明記する。

## 指標
- acquired_cookies = 初回sessionが獲得期間内の `COUNT(DISTINCT cookie)`。
- logged_cookies = そのcookieで観測終了までに会員観測があった `COUNT(DISTINCT cookie)`。
- login_rate = logged_cookies / acquired_cookies。
- purchasing_cookies = ログイン後に帰属された注文がある `COUNT(DISTINCT cookie)`。
- orders = 正規化後のログイン後帰属注文数。sales = その注文合計金額の合計。
- purchase_rate = purchasing_cookies / acquired_cookies。会員数を分母にした転換率は別名にする。
- cohort_roas = 初回landing獲得コホートの追跡売上 / 同じ獲得日・source・medium・campaign・content・term・通貨の広告費 ×100。
- CPA = spend / acquired_cookies。比較指標の分母は必ずラベルに出す。

広告費未入力・0円・粒度不一致・通貨不一致・金額不明注文ありはROASをNULLにする。NULLを0に見せない。広告費があり獲得0の行も残す。異なる通貨を合算しない。v1の入力は単一通貨で固定し、複数通貨は為替契約を決めた上で別拡張する。

7/30/90日比較は同じ観測可能期間があるコホートに限定するか、未成熟コホートを明示する。v1テンプレートのsalesは観測終了までの累積であり、固定90日LTVではない。分析スナップショットの観測終了・経過日数を必ず表示する。

## 再構築・更新と安全性
出力は `<prefix>_<mart>_<session_unixtime>_<attempt_id>` の試行別テーブル。過去成功テーブルを上書きしない。中間テーブル、QA、完了テーブルの順に構築する。QAが失敗した試行は完了テーブルを作らず、ダッシュボードにも反映しない。不要テーブル削除は別途一覧・保持方針・承認が必要。

v1は単純さと正確さを優先し、増分処理・watermarkを実装しない。大規模環境はセッション継続、遅延到着、初回台帳、ログイン補完、注文更新/返品を含めた増分設計を別途承認する。単純な直近7日再集計で全履歴を置換しない。

作成 Treasure Work
