# カート・ブラウザ放棄 Workflow テンプレート

`mode: cart | browser | both` を **`config/params.yml`** で選ぶ、正規化入力（canonical schema）ベースの共通実装です。`cart_abandonment.dig` がこのファイルを直接 include します。`params.example.yml` は同内容の配布用見本で、実行時の参照先ではありません。動作変更にランタイムの `-p` は使用しません。

**配布状態ではスケジュールなし、`workflow.enabled: false`、本番・テスト配信とも無効です。** 無効状態では TD の読み書きも行いません。enable/approval・optionalフラグは引用符なしのYAML真偽値、秒数・上限はYAMLの有限な非負整数で指定します。文字列の `"false"` / `"100"` などは事前検査で拒否します。設定・スキーマ・接続を確定するだけでは配信を承認したことになりません。最初に付属 Skill のヒアリングを行ってください。

## エントリーポイント

| ファイル | 用途 |
|---|---|
| `cart_abandonment.dig` | 全モード共通の抽出・任意配信。`window.kind` で rolling / overnight を選択 |
| `send_email_test.dig` | 明示承認した宛先だけに、決定的な**合成データ**を送る独立テスト経路。既定無効 |
| `cart_abandonment_nightly.dig` | 廃止入口。誤った二重実行を避けるため `fail>` で停止 |
| `send_email.dig` | 廃止入口。古い送信リストの単独配信を禁止するため `fail>` で停止 |
| `tests/test_workflow.py` | ローカル専用テスト。TD・メール・ネットワークを使用しない |

本番配信には `workflow.enabled`、`delivery.enabled`、`delivery.approved` と必要な配信資産の設定が必要です。`browser` ではカート用 Campaign・カート送信テーブル・カート専用履歴は不要です。ただし **ブラウザ施策の抑止に使うカートイベント**は必要です。`both` は会員単位でカートを優先し、1実行で同じ会員に2施策を選びません。

## 入力を最初に正規化する

`adapters/canonical_schema.sql` に正確な列名・型を定義しています。このファイルは**自動実行されません**。DB作成・テーブル作成・ソースからのマッピングには別途承認が必要です。`adapters/source_mapping.example.sql` は仮想的な行形式ソースから events / recipients / orders を作る具体例であり、実アカウントのテーブルが存在するという意味ではありません。顧客固有の判定はこのアダプタ層に実装し、共通SQLへ埋め込まないでください。

### 常に必要な入力

| 設定 | 粒度と必須契約 |
|---|---|
| `sources.events` | 1行=1イベントの商品1件。`time` は**業務イベントの Unix 秒**兼 canonical の TD 時間パーティション。`event_id, device_id, member_id, event_type, product_id, quantity, item_position` と商品表示列 |
| `sources.identities` | `device_id → member_id` の確認済み履歴。`updated_at, row_id` を保持。全イベントに会員IDがあれば空でも可 |
| `sources.recipients` | 会員ごとの変更履歴。`member_id, email, consent, suppressed, updated_at, row_id`。配信停止・削除・NULL状態も残す |
| `sources.orders` | 注文明細。`time, order_id, member_id, product_id, cancelled`。オンライン以外も含む確認済み購買シグナル |
| `sources.history` | **全モードで共有する予約台帳**。`member_id, kind, decision_id, time, status, attempt_id`。存在しなければ共通WFが作成 |

- `event_type` は `activity / product_view / cart_item / cart_clear / purchase`。PDP以外の閲覧・操作も `activity` として残します。これがないと直近活動ガードが成立しません。ボット除外とPDP/購入判定はソースに合わせてアダプタで確認します。
- **カートは完全スナップショット**です。同じ `event_id` の `cart_item` 行を全商品分出し、同一の時刻・会員を設定します。空になった最新状態は、商品IDなしの `cart_clear` を1行出します。単なる `add_to_cart` 差分を名前だけ変更してはいけません。差分は上流で追加・削除・数量変更を再構成してください。
- `product_view` は1イベント1商品。最新PDPの商品ID・URL・商品公開状態が不正でも、古いPDPへ戻りません。最新カートを選んだ後に商品を絞り込むため、削除済み商品も復活させません。
- `event_id` はアクション単位でグローバルに一意とし、同一秒では辞書順の大きいIDを新しいものとして扱います。ただし同じ秒の `cart_clear` は商品あり状態より常に優先して安全側に倒します。`row_id` も同一 `updated_at` の変更順を決めます。**ソースの順序を保持するキーへマッピング**し、順序不明の競合状態は上流で隔離してください。商品配列の並びは `item_position` です。
- IDは同じ会員を表す安定した文字列へ統一します。欠損Cookieを共有の固定値へ置き換えてはいけません。匿名イベントは確認済みで曖昧でない device 対応だけで会員へ解決します。既知の共有端末に複数会員が結び付く場合、**結び付く全会員を他端末の行も含め除外**します。自動的な推測・確率的な名寄せは行いません。
- メールはアダプタでの正規化に加え、共通SQLでも `LOWER(TRIM(email))` で正規化します。会員IDとの対応・同意の意味を確認し、**最新行を選んでから**同意・抑止を判定します。同じメールが複数会員に結び付く場合、NULL同意・NULL抑止、時刻/行ID欠損の変更行がある会員、最新の同一時刻/同一行IDで内容が矛盾する会員は配信不可です。抽出時とexport直前の両方で確認します。
- 注文テーブルを空にできるのは、Web購入の完全性を確認し、減る保護範囲を明示承認した場合だけです。ゲスト注文・端末共有・未取得チャネル・遅延到着などで会員に結び付けられない購買は自動では除外できません。**未確認のまま本番化しないでください。**
- 生ログの取り込み `time` と業務イベント日時が異なる場合は、遅延分を含む取り込みパーティションを読んで業務時刻へ変換します。ミリ秒をそのまま渡してはいけません。ソース鮮度・購入/同意データの遅延は上流watermark等で別途確認します。このWFはデータの完全到着を保証しません。

### 設定で任意に有効化する入力

`personalization` の各フラグが `false` の場合、その**ソース表は読まず、存在も要求しません**。型付きの空ステージング表だけを作成します。

| フラグ | canonical入力と実装範囲 |
|---|---|
| `products` | 商品IDごとの変更履歴。最新行の `published / available` を判定し、商品名・URL・画像・ブランド・価格・通常価格・`low_stock` を付与。最新が非公開/在庫なしなら旧行を復活させない |
| `recommendations` | 会員別の**完全な推薦スナップショット**。`snapshot_at` 最新を採用し、`updated_at, row_id` で商品重複を解決、`position, product_id` 順で最大4件。カート/閲覧商品との重複を除外。空の最新スナップショットは `product_id=NULL, available=false` 行で表す |
| `attributes` | 会員別最新行の `points / segment`。セグメントを計算する顧客固有ロジックは上流 |
| `coupons` | 会員別最新オファー。最新行を選んだ後で `active` と `valid_from <= as_of < valid_until` を確認。期限切れ/撤回時は旧クーポンを復活させず、表示列を空にする |

`products: false` ではイベント内の商品表示情報を使用し、現在の在庫・公開状態を確認しません。この制約を受け入れるか、商品アダプタを有効にしてください。商品リンクはHTTPSかつ商品名ありを必須とし、不正画像URLは空にします。HTML/Liquid側でもエスケープと空項目非表示を実装してください。

## 検出窓・購入除外・頻度キャップ

1. `session_unixtime` を固定の `as_of` とし、`[as_of-scan.lookback_seconds, as_of)` のイベントを読みます。全端末を会員単位にまとめ、無操作時間でセッション化します。
2. **会員の最新セッションを先に選び**、その後で対象窓と待機時間を判定します。新しい非PDP活動・別端末活動があれば、古い対象セッションを復活させません。
3. rolling は `[as_of-max_age_seconds, as_of-inactivity_seconds)`。overnight は「前のSQLローカル日付の `overnight_start`」から「当日の `overnight_end`」までの半開区間を使い、終了は待機時間でも切り詰めます。時刻は設定値で、特定の8時処理はありません。開始時刻は終了時刻より後であることが必要です。DSTもローカル日付で計算します。
4. `inactivity_seconds >= session_timeout_seconds + expected_latency_seconds` を要求します。scanは候補窓・セッション境界・購買/カート除外・cap期間を包含する必要があります（overnight用に最低2日+session境界も要求）。待機設定だけで上流遅延を解決したことにはなりません。
5. 同一セッションの購入、対象行動後の購入、設定期間内の直近購入を**会員・全端末共通**で除外します。注文とWeb購入の両方を使います。キャンセル注文だけでは抑止しません。
6. ブラウザ施策は、同一セッション・PDP後・設定期間内のカート操作/空カート操作でも除外します。カート候補が商品条件・同意・capで落ちても、ブラウザへフォールバックしません。
7. capは共有台帳の `reserved / accepted / delivered` を `decision_id` 単位で数えます。`per_kind` と `total` は両モード共通の規則。`period: rolling` は `as_of-window_seconds` 以降、`calendar_day` はSQLタイムゾーンの当日0時以降です。遅延実行中に記録された後続attemptの予約も数え、as_ofで上限を切りません。同一IDの重複台帳行は二重計上しません。

**タイムゾーンは2層あります。** `.dig` の `timezone: UTC` はWorkflowの論理セッション/将来設定するschedule用です。`config.timezone: UTC` はSQLのovernight・日次cap用で、IANA名へ変更できます。両者を同じ設定だと誤認しないでください。

## 出力・配信安全性

`output.database / prefix` 以下の `_events / _candidates / _products / _recommendations / _attributes / _coupons / _items / _send_list` は再作成するステージングです。`create_table` はTrino系のDROP+CTASで、atomic swapではありません。Parent Segment等へ常時公開する既存表をそのまま指定せず、安定公開用アダプタを別途設計してください。

最終出力は会員・メール各1件で、主な列は次のとおりです。

- `run_time, member_id, email, kind, decision_id, detected_at, variant`
- `item_1_*`〜`item_4_*`：`product_id, item_name, item_url, image_url, brand, price, original_price, quantity, low_stock`
- `recommend_1_*`〜`recommend_4_*`：商品ID・名前・URL・画像・ブランド・価格・通常価格
- `points, segment, coupon_code, coupon_description, coupon_image_url, coupon_valid_until`

外部へ渡すのは `email` とパーソナライズ列（`kind / detected_at / variant` を含む）だけです。内部の `member_id / run_time / decision_id` は外部exportから除外します。台帳の `attempt_id` を追加するため、既存台帳はスキーマを確認・承認した上で移行してください（`CREATE IF NOT EXISTS` は列を自動追加しません）。

ブラウザは最新閲覧商品の1枠、カートは最新スナップショットから最大 `max_items`（1〜4）枠です。`variant` は `normal / low_stock`。価格は表示用文字列、時刻はUnix秒です。**旧Liquid変数名（例 `cart_item_seq1_*`）とは別スキーマ**です。既存テンプレートへ無確認で接続せず、マッピングSQLまたはテンプレートを移行してください。

配信を有効にした場合のみ、最終件数/メール重複・最大対象数・実時計と論理セッションの差を確認し、確定payloadの `decision_id` を共有台帳へ**予約してから**エクスポートします。キーは長さ付きの会員ID・施策・ソース `event_id` から生成し、as_ofが変わっても同じ行動では不変です。過去に同じキーの台帳行があればcap期間外でも再選択せず、予約直前にも既存キーの混入を検査して停止します。予約は `attempt_id` に結び付け、exportは同じattemptの予約だけを認めます。0人では予約/エクスポートを実行しません。各export SQLでも予約と実行遅延を再確認し、**現在の最新同意・メール変更・共有メールを再確認**します。後からの停止は予約済み集合を減らすだけで、新しい会員を追加しません。遅いbackfillは配信不可です。

**重要：同じ出力・台帳を使う全プロジェクト/手動実行/定期実行を、運用側で必ず直列化してください。** WF内は順次処理ですが、別attempt間の排他ロックや台帳の一意制約は実装していません。`NOT EXISTS` は原子的な予約ではなく、複数writerでの重複やconnectorの不明応答を防げません。exactly-once配信を保証しません。

予約・本番/テストexportは `job_retry: 0`、Workflowの `_retry` も設定しません。**同一attemptのexportから手動再開すると予約が同じため重複し得ます。exportからの手動resumeは禁止し、attempt IDが変わるかも実環境で確認してください。** これはprovider内部の再送を保証するものではありません。失敗時は予約を配信済みと呼ばず、provider結果を照合してから再開/再送を判断してください。プレビュー生成のみでは台帳を消費しません。

## 合成データによるテスト配信

`send_email_test.dig` はライブのイベント・宛先・注文・履歴を**一切読みません**。`queries/test_fixture.sql` の定数だけから本番exportと同じ列構成（内部会員/実行/予約メタデータは含めない）のpayloadを作り、`email` は必ず確認済みテスト宛先へ設定します。

- `testing.enabled / approved` は両方とも既定 `false`。宛先 `recipients` と明示的 `allowlist` は空です。
- `testing.connection / workspace_id / cart_campaign_id / browser_campaign_id` は専用テスト資産を設定します。接続・Workspace・Campaignを設定済み本番資産と同じにはできません。選択していない施策のCampaignは不要です。実際に隔離されたテスト環境かは別途確認が必要です。
- smokeは `normal` 1種、fixtureは `normal / low_stock` 2種、fullは `minimal / normal / low_stock` 3種。`expected_messages = 宛先数 × 有効施策数 × 種類数` と `max_messages` を実行前に検証します。
- optional列は `personalization` のフラグに従って埋めます。minimalはoptional列なし、low_stockは在庫僅少表示用の合成値です。`example.invalid` のダミー画像/商品URLは実在しません。実際の画像表示確認前に、承認済みテスト資産へfixtureを調整してください。
- テスト配信も外部送信です。正確な宛先・資産・想定通数について承認し、インストール済みCLIのhelpで構文を確認してdry-runをレビューした後にのみ実行します。このリポジトリの作業では実行していません。

## ローカル検証（送信なし）

Python 3.9+（SQLite window関数・zoneinfo）、Ruby/Psych、Nodeが必要です。追加パッケージ不要。`testing.mode` を設定して、プロジェクト内で次を実行します。

```bash
python3 -I tests/test_workflow.py
```

全ケースを明示して実行するローカル専用オプションは `python3 -I tests/test_workflow.py --mode full` です。これはTD Workflowのランタイムパラメータではありません。

YAML/重複キー、Digdag条件・ループ、全SQL変数展開、3施策モード、rolling/overnight/DST境界、名寄せ曖昧性、空カート・最新不正PDP・直近活動、購買除外、同意/商品最新行、共有cap、推薦/属性/クーポン、予約とpayloadの一致、現在同意/実行遅延、テスト宛先強制/通数/本番資産混同防止を検証します。ローカルプレビューはHTMLエスケープ/列契約確認であり、EngageのLiquid実レンダリング検証ではありません。

**検証境界：** 実SQLをSQLiteで実行し、TD時刻UDFをローカル実装・TrinoのDATE演算1箇所を明示変換します。実機Trino、TD hosted Digdag、connector、実テンプレート、実データの意味/性能は未検証です。ローカル成功はTD成功ではありません。存在を確認していない `tdx wf validate` は案内しません。デプロイ・スケジュール変更・TD実行・テスト送信は、対象と副作用を説明して別途明示承認を得てください。

## 旧カート実装からの移行と参照範囲

旧汎用カート実装の `.dig / SQL / config` 24ファイルは、`reference/legacy-cart/**/*.txt` に**非実行の参考資料**として保持しました。クーポンの固定文言/期限はプレースホルダーへ置換し、危険な旧運用コマンドは廃止注記へ置換しています。ここを直接デプロイしたり、旧手順を実行したりしないでください。

- 現行coreには複数カート商品、最新ブラウザ商品、商品公開/在庫/価格、在庫僅少variant、最大4推薦、ポイント/セグメント、期限付きクーポンのcanonical接続があります。
- 旧実装の独自RFM算出、共閲覧/同時購入/人気/購入済み除外を組み合わせた推薦生成、旧Liquid列名、施策別の複数Campaign割り当て、旧履歴全項目、実メールからの代表パターン抽出は自動移植していません。推薦生成とセグメント/offer選定は上流アダプタ、列互換は出力アダプタとして要件確認・実装・テストします。
- 最長滞在商品・日またぎ滞在時間補完ではなく、coreは**最新閲覧商品**を表示します。滞在時間方式が必要なら、秒単位の滞在時間とepoch時刻を混同しない独立アダプタを追加してください。
- 旧カート/ブラウザ履歴は会員ID・施策種別・安定キー・時刻・予約/送信状態を確認して共有台帳へ移行します。候補を保存しただけの履歴を「配信完了」と解釈しません。別施策との総capが必要なら、その履歴もcanonical台帳へ統合する設計が必要です。

旧機能がこのまま全て動くという互換性は約束しません。必要なcart機能をヒアリングし、参照SQLのロジックと期待値を維持するアダプタを作ってから移行してください。
