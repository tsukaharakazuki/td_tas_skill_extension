# td_datafeed データフィード構築スキル

Treasure Dataで商品データフィードを構築するための日本語スキルです。

## このスキルの特徴

いきなりBASE SQLを作成しません。以下の順番でヒアリングしてから、BASE SQLとチャネル別フィードを構築します。

```text
1. 連携したいチャネルを確認
2. 選択チャネルに必要な商品項目を整理
3. 必要項目がどのDB/TBL/カラムに格納されているか確認
4. テーブル粒度・JOINキー・履歴の最新行を確認
5. 在庫・価格・販売期間・予約・URL生成ルールを確認
6. ヒアリング結果からBASE SQLを生成
7. JOIN重複・未一致・必須キーを検証
8. 選択したチャネルのWorkflowと出力設定を作成
```

## 対応チャネル

- Google Merchant
- Meta Organic
- Meta Dynamic
- Meta Collection
- Criteo Catalog
- RTB House DataFeed
- Yahoo Shopping Ads

Criteo、RTB House、Yahoo Shopping Adsは、公式仕様を確認するまで仮マッピングとして扱います。公式の必須項目・ファイル形式・文字コード・区切り・ヘッダー・アップロード方法が確認できるまでは、本番出力を有効化しません。

## 使い方

1. `SKILL.md` を読み込む。
2. `CHANNEL_FIELD_MATRIX.md` で連携チャネルを選ぶ。
3. `SOURCE_TABLE_HEARING.md` に沿ってDB/TBL/カラムを確認する。
4. `BASE_FEED_SPEC.md` でJOIN設計とBASE出力項目を確認する。
5. ヒアリング結果をレビューし、`examples/queries/base_feed.sql` を対象環境用に生成・更新する。
6. BASE検証後に、選択したチャネルのサンプルWorkflowを利用する。

## ファイル構成

```text
datafeed-tools/td-datafeed-workflow/
├── SKILL.md
├── README.md
├── CHANNEL_FIELD_MATRIX.md
├── SOURCE_TABLE_HEARING.md
├── BASE_FEED_SPEC.md
└── examples/
    ├── config/params.yml
    ├── td_datafeed.dig
    ├── export.dig
    ├── channel_*.dig
    └── queries/
        ├── base_feed.sql
        ├── feed_*.sql
        └── validate_*.sql
```

## 注意

- `examples/` はサンプルです。クライアントのDB/TBL/カラムへ置き換えてください。
- `YOUR_*` が残った状態で実行しないでください。
- コネクタ名、バケット、URL、アカウント情報、認証情報はサンプルへ直書きしません。
- Workflowのpush・実行・外部ファイル出力は、設定と対象件数を確認し、明示的な承認後に行ってください。
