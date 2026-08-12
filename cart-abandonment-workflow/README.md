# カート放棄Workflow

Treasure Dataでカート放棄者を検出し、メール配信用の送信リストを作成するための、顧客非依存のSkillとDigdag Workflowサンプルです。

## 内容

- `SKILL.md` — カート放棄Workflowを構築する際のヒアリング、設計、テスト、検証手順
- `cart-abandonment/` — 実際のDigdag Workflow、SQL、設定テンプレート

## 使い方

1. `SKILL.md` を読み込む。
2. `cart-abandonment/config/params.example.yml` を顧客用設定のベースとしてコピーする。
3. Webログ、カート条件、購入除外、同意条件、出力先、配信経路をヒアリングする。
4. 顧客用Workflowコピーを作成し、`<...>` プレースホルダーを置き換える。
5. SQL、YAML、Digdag構造を検証する。
6. dry-runでタスクグラフと外部送信範囲を確認する。
7. 明示的な承認後にのみテスト送信・本番送信を実行する。

## テストWorkflow

テストの `.dig` エントリーポイントは `cart-abandonment/send_email_test.dig` の1つです。実行時の `test_mode` でテスト範囲を切り替えます。

```bash
tdx wf run cart_abandonment.send_email_test -p test_mode=smoke
tdx wf run cart_abandonment.send_email_test -p test_mode=fixture
tdx wf run cart_abandonment.send_email_test -p test_mode=full
```

- `smoke`：最大表示・最小表示を確認する初回テスト
- `fixture`：カート数、在庫、レコメンド、ポイントなどの代表パターンを確認するテスト
- `full`：送信履歴に存在するパターンを網羅するテスト

テスト送信前に、テスト宛先と本番から分離されたテストキャンペーンを設定し、想定メッセージ数を確認してください。

## 注意

このサンプルには顧客の認証情報や本番キャンペーン情報を含めません。`params.example.yml` のプレースホルダーを残したまま実行しないでください。
