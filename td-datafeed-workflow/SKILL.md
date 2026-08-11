---
description: "td_datafeedで連携チャネルをヒアリングし、必要項目のDB/TBL/カラムとJOINキーを確認してからBASE SQLとチャネル別フィードを構築する。"
---

# td_datafeed データフィード構築スキル

## このスキルの役割

このスキルは、Treasure Data Workflowで商品データフィードを構築するときに使用します。

最初からSQLを書き始めません。次の順番で利用者にヒアリングし、確認済みの情報だけを使ってBASE SQLを作成します。

```text
連携チャネルの選択
  → チャネルに必要な項目の整理
  → 各項目のDB/TBL/カラム確認
  → テーブルの粒度・JOINキー・履歴条件確認
  → 在庫・販売・URL等の業務ルール確認
  → BASE SQL作成
  → BASE検証
  → チャネル別SQL・出力設定
```

## 最初に必ず行うヒアリング

### 1. 連携チャネルを確認する

利用者に、次のどのチャネルを連携したいか確認します。複数選択可です。

- Google Merchant
- Meta Organic
- Meta Dynamic
- Meta Collection
- Criteo Catalog
- RTB House DataFeed
- Yahoo Shopping Ads

チャネルが決まる前に、BASE SQLや`config/params.yml`を確定させません。

### 2. 必要項目を逆算する

`CHANNEL_FIELD_MATRIX.md`を参照し、選択されたチャネルについて以下を整理します。

- 必須項目
- 推奨項目
- 任意項目
- 公式仕様が未確認の項目
- 複数チャネルで共通利用できる項目

Criteo、RTB House、Yahoo Shopping Adsは雛形段階では仮マッピングです。公式仕様を確認するまで「必須」と断定せず、`REVIEW_REQUIRED`として扱います。

### 3. DB/TBL/カラムの所在を確認する

`SOURCE_TABLE_HEARING.md`を使って、必要項目ごとに以下を確認します。

- DB名
- テーブル名
- カラム名
- データ型
- 1行の粒度
- 主キー/候補キー
- 更新日時・有効期間
- 論理削除・公開フラグ
- 店舗、販売チャネル、倉庫、ロケーションの絞り込み

テーブル名だけでは不十分です。選択チャネルに必要な項目がどのカラムに入っているかまで確認します。

## JOIN設計の確認

JOINはカラム名が似ているという理由だけで決めません。

各JOINについて、利用者に次を確認します。

- 左右のテーブルとカラム
- キーの意味
- データ型
- 1対1、1対多、多対多の関係
- JOIN後に維持したいBASEの粒度
- INNER JOINかLEFT JOINか
- 履歴テーブルの最新行を決めるカラム
- 店舗/倉庫/チャネルのスコープ

不明なJOINキーは推測せず、確認事項として残します。

## BASE SQLを作成する条件

次の条件をすべて満たしてから、`queries/base_feed.sql`を作成または更新します。

- 連携チャネルが決まっている。
- 選択チャネルの必要項目が一覧化されている。
- 必須項目のDB/TBL/カラムが確認されている。
- BASEの1行の粒度が決まっている。
- JOINキー、JOIN種別、JOIN後の粒度が確認されている。
- 履歴の最新行の決め方が確認されている。
- 在庫、販売期間、予約、公開範囲のルールが確認されている。
- 商品URL・画像URLの生成ルールが確認されている。

情報が不足している場合は、SQLに推測のテーブル名・カラム名・固定値を入れません。`YOUR_*`または「要確認」として止めます。

## BASE SQLの生成後

1. `queries/base_feed.sql`を生成する。
2. `queries/validate_base_feed.sql`で件数、必須キー、価格、URLを確認する。
3. JOIN前後の行数、重複、未一致を確認するSQLを用意する。
4. 利用者にSQLのJOINとフィルタをレビューしてもらう。
5. 承認後、選択チャネルの`feed_*.sql`をBASEに接続する。
6. チャネルの検証SQLと出力ファイル名を設定する。

## ファイル構成

```text
workflows/td_datafeed/
├── config/params.yml
├── CHANNEL_FIELD_MATRIX.md
├── SOURCE_TABLE_HEARING.md
├── BASE_FEED_SPEC.md
├── td_datafeed.dig
├── channel_google.dig
├── channel_meta_organic.dig
├── channel_meta_dynamic.dig
├── channel_meta_collection.dig
├── channel_criteo_catalog.dig
├── channel_rtb_house.dig
├── channel_yahoo_shopping.dig
├── export.dig
└── queries/
    ├── base_feed.sql
    ├── validate_base_feed.sql
    ├── feed_*.sql
    └── validate_*.sql
```

OPT処理は含めません。

## 重要な注意

- Criteo、RTB House、Yahoo Shopping Adsの仕様未確認チャネルは、本番送信を有効化しません。
- コネクタ名、バケット、URL、アカウント情報、認証情報をスキルやSQLに直書きしません。
- OneDrive/S3の出力先は`config/params.yml`で管理し、初期状態では無効です。
- 0件、必須キー欠損、JOINによる行数増殖がある場合は送信しません。
- `tdx wf push`やWorkflow実行は、SQL・接続先・対象件数を確認し、利用者の明示的な承認を得てから行います。
