# カート放棄Workflowサンプル

カート放棄の対象者を検出し、送信リストを作成し、必要に応じてEngage StudioのAlways-On Campaignへ配信するための、顧客非依存のTreasure Data Workflow（Digdag）サンプルです。

このディレクトリはテンプレートです。`.claude/skills/cart-abandonment-workflow/SKILL.md` のヒアリングを完了し、`config/params.example.yml` を顧客用の設定へ置き換えてから使用してください。

## 処理フロー

1. リアルタイムまたはバッチのWebログを読み込む。
2. 訪問者の行動をセッション化する。
3. 無操作時間を経過したカート放棄候補を抽出する。
4. 購入者、配信停止者、抑止対象者、頻度キャップ超過者を除外する。
5. 商品、在庫、レコメンド、ポイント、クーポン情報を必要に応じて付与する。
6. 配信用の送信リストを作成する。
7. 設定済みのAlways-On Campaignへ任意で結果をエクスポートする。
8. 宛先をテスト用に置き換え、テンプレート変数をダミー値で埋めるモード切替式テストを実行する。

## テストの実行

テストのエントリーポイントは `send_email_test.dig` です。テスト段階ごとに複数の `.dig` ファイルを作らず、次のモードで切り替えます。

```bash
tdx wf run cart_abandonment.send_email_test -p test_mode=smoke
tdx wf run cart_abandonment.send_email_test -p test_mode=fixture
tdx wf run cart_abandonment.send_email_test -p test_mode=full
```

SQLはデータ抽出方法が異なるため、smoke、fixture、fullの用途別に分かれています。

## 顧客ごとに確認する設定

- 対象DBと出力テーブルのプレフィックス
- Webログの取得元とデータ鮮度
- 識別子、Cookie、商品カラム
- カート条件と購入条件
- 配信先・同意データの取得元
- 注文除外期間と頻度キャップ
- パーソナライズ項目とテンプレート仕様
- Engage Studioのキャンペーン、Workspace、接続、または外部コネクタ設定
- テスト宛先とテストキャンペーン

## 命名と安全性

サンプルでは `cart_abandonment`、`source_web_events`、`target_cart_send_list` のような汎用名を使用しています。顧客用コピーでは `<TO_BE_CONFIRMED>` などのプレースホルダーを置き換えてください。顧客名、内部アカウントID、実メールアドレス、認証情報、本番キャンペーンIDをサンプルへ追加しないでください。

検証とdry-runを先に実施してください。dry-runは送信ではありませんが、テストWorkflowや外部コネクタを実行する前にも対象範囲と送信先について明示的な承認を得てください。
