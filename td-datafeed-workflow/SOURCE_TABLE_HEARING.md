# DB・テーブル・カラム ヒアリングシート

BASE SQLを作成する前に、連携チャネルに必要な情報がどこに格納されているかを確認します。

テーブル名だけでなく、必要なカラム、データ型、キーの意味、更新履歴、レコード粒度まで確認してください。

## 1. まず確認する全体条件

| 確認項目 | 回答 |
|---|---|
| 対象DB | `YOUR_DATABASE` |
| BASEの1行の粒度 | SKU / 商品 / その他 |
| 連携対象期間 | `YOUR_PERIOD_RULE` |
| 対象店舗/販売チャネル | `YOUR_STORE_OR_CHANNEL_SCOPE` |
| 対象倉庫/ロケーション | `YOUR_LOCATION_SCOPE` |
| タイムゾーン | `YOUR_TIMEZONE` |
| 国・通貨 | `YOUR_COUNTRY` / `YOUR_CURRENCY` |
| URL生成方法 | `YOUR_URL_RULE` |
| 画像URL生成方法 | `YOUR_IMAGE_URL_RULE` |

## 2. 論理役割ごとのヒアリング

### SKU・バリエーション・価格

- DB名:
- テーブル名:
- 1行の粒度: SKU / 商品 / その他
- SKU ID:
- SKUコード:
- 親商品ID:
- 親商品コード:
- 税抜通常価格:
- 税込通常価格:
- 税抜販売価格:
- 税込販売価格:
- 色:
- サイズ:
- バリエーション画像キー:
- 更新日時:
- 削除/公開ステータス:

### 商品マスタ

- DB名:
- テーブル名:
- 商品ID:
- 商品コード:
- 商品名:
- マーチャント商品コード:
- ブランドID:
- 表示ブランドID:
- カテゴリID:
- 年/シーズン:
- 更新日時:
- 削除/公開ステータス:

### 商品説明・属性

- DB名:
- テーブル名:
- 商品IDまたはSKU ID:
- 商品説明:
- HTMLの有無:
- 素材:
- 原産国:
- 性別:
- タグID:
- 更新日時:
- 最新行を決める列:

### 販売・公開情報

- DB名:
- テーブル名:
- 商品IDまたはSKU ID:
- 店舗/チャネルID:
- 販売ステータス:
- 公開フラグ:
- 販売開始日時:
- 販売終了日時:
- 公開開始日時:
- 公開終了日時:
- 予約フラグ:
- 入荷予定日:
- 更新日時:

### 在庫・販売上限

- 在庫DB名:
- 在庫テーブル名:
- 在庫のキー:
- 倉庫/ロケーション列:
- 引当可能在庫列:
- 在庫更新日時:
- 販売上限DB名:
- 販売上限テーブル名:
- 販売上限のキー:
- 販売上限列:
- 在庫と販売上限の優先ルール:

### ブランド・ブランド対応

- 表示ブランドDB/テーブル:
- 表示ブランドID:
- 表示ブランド名:
- URL用ブランド略称:
- 管理ブランドDB/テーブル:
- 管理ブランドID:
- 表示ブランドとの対応テーブル:
- 最新行の判定列:

### カテゴリ

- DB名:
- テーブル名:
- カテゴリID:
- 商品カテゴリ名:
- Googleカテゴリ:
- カテゴリの更新日時:
- 削除/有効フラグ:

## 3. JOIN確認表

| No. | 左テーブル.キー | 右テーブル.キー | 関係 | JOIN種別 | 最新行条件 | 回答/確認事項 |
|---|---|---|---|---|---|---|
| 1 | SKU.`YOUR_KEY` | 商品.`YOUR_KEY` | 1:1 / 1:N | INNER / LEFT | あり/なし | |
| 2 | SKU.`YOUR_KEY` | 販売.`YOUR_KEY` | 1:1 / 1:N | INNER / LEFT | あり/なし | |
| 3 | SKU.`YOUR_KEY` | 在庫.`YOUR_KEY` | 1:1 / 1:N | INNER / LEFT | あり/なし | |
| 4 | 商品.`YOUR_KEY` | 説明.`YOUR_KEY` | 1:1 / 1:N | INNER / LEFT | あり/なし | |
| 5 | 商品.`YOUR_KEY` | ブランド.`YOUR_KEY` | 1:1 / 1:N | INNER / LEFT | あり/なし | |
| 6 | 商品.`YOUR_KEY` | カテゴリ.`YOUR_KEY` | 1:1 / 1:N | INNER / LEFT | あり/なし | |

### JOINで必ず確認すること

- 列名が同じでも、キーの意味が同じか。
- キーのデータ型が一致しているか。
- JOIN前後で1行の粒度が変わらないか。
- 1対多の場合、最新行・代表行・集約方法は何か。
- 履歴テーブルの最新行を決める列は何か。
- 論理削除・公開状態・無効レコードを除くか。
- 店舗、チャネル、倉庫、ロケーションをどの条件で限定するか。
- LEFT JOINで欠損を許容する項目か、INNER JOINで必須にする項目か。

## 4. 回答の記入例

```yaml
base_grain: sku
source_database: YOUR_DATABASE
sources:
  sku:
    table: YOUR_SKU_TABLE
    key: sku_id
    parent_key: product_id
    updated_at: imported_at
  product:
    table: YOUR_PRODUCT_TABLE
    key: product_id
    updated_at: imported_at
  sales:
    table: YOUR_SALES_TABLE
    key: sku_id
    updated_at: imported_at
    scope:
      store_id: YOUR_STORE_ID
  stock:
    table: YOUR_STOCK_TABLE
    key: sku_id
    updated_at: imported_at
    scope:
      location_id: YOUR_LOCATION_ID
joins:
  - left: sku.product_id
    right: product.product_id
    relationship: many_to_one
    join_type: inner
  - left: sku.sku_id
    right: sales.sku_id
    relationship: one_to_one_after_latest_filter
    join_type: left
  - left: sku.sku_id
    right: stock.sku_id
    relationship: one_to_one_after_latest_filter
    join_type: left
```

## 5. BASE SQL作成の開始条件

以下がすべて埋まるまで、BASE SQLを本番用として生成しません。

- 選択した連携チャネルが決まっている。
- チャネルごとの必須項目が確認できている。
- 各必須項目のDB・テーブル・カラムが決まっている。
- BASEの1行の粒度が決まっている。
- JOINキーの意味・型・関係・JOIN種別が確認できている。
- 履歴テーブルの最新行ルールが決まっている。
- 在庫、販売期間、予約、公開範囲のルールが決まっている。
- URL・画像URLの生成ルールが決まっている。

不明点がある場合は、SQL内に推測で固定値を入れず、要確認事項として残します。
