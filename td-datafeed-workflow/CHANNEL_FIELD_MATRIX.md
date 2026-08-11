# 連携チャネル別 必要項目一覧

この資料は、BASEデータに必要な情報を洗い出すためのヒアリング用です。

最初に利用者へ連携チャネルを確認し、選択されたチャネルの「必須」「推奨」「任意」項目を合算して、BASEに必要な項目を決めます。

> Criteo Catalog、RTB House DataFeed、Yahoo Shopping Adsは、現在の雛形SQLに基づく仮マッピングです。公式仕様の確認が完了するまで、必須項目として確定しないでください。

## 1. 連携チャネルの選択

- [ ] Google Merchant
- [ ] Meta Organic
- [ ] Meta Dynamic
- [ ] Meta Collection
- [ ] Criteo Catalog
- [ ] RTB House DataFeed
- [ ] Yahoo Shopping Ads

## 2. 共通項目

| 論理項目 | 内容 | 主な利用チャネル | BASEでの扱い |
|---|---|---|---|
| `id` | 連携先で一意なSKU/商品ID | 全チャネル | 必須。SKU単位か商品単位か確認 |
| `item_group_id` | バリエーションを束ねる親商品ID | Google、Meta等 | 親子関係を確認 |
| `title` | 商品名 | 全チャネル | 必須。言語・文字数制限を確認 |
| `description` | 商品説明 | Google、Meta、Criteo、RTB House、Yahoo | HTML・改行・NULLの扱いを確認 |
| `link` | 商品ページURL | 全チャネル | URL生成元とパラメータ付与を確認 |
| `image_link` | 商品画像URL | 全チャネル | SKU画像か商品画像か確認 |
| `availability` | 在庫状況 | 全チャネル | 在庫数・予約区分からの判定を確認 |
| `stock_quantity` | 在庫数 | 全チャネルの絞り込み/ラベル | 倉庫・引当・販売上限の優先順位を確認 |
| `price` | 通常価格 | 全チャネル | 税込/税抜・通貨を確認 |
| `sale_price` | セール価格 | Google、Meta、Criteo、Yahoo等 | 通常価格との差分・NULL処理を確認 |
| `sale_price_effective_date` | セール期間 | Google、Meta等 | 開始/終了日時の型とタイムゾーンを確認 |
| `brand` | ブランド名 | 全チャネル | 表示名と管理IDの対応を確認 |
| `brand_abb` | URL用ブランド略称 | Meta等 | URL生成に必要か確認 |
| `product_type` | 商品カテゴリ | Google、Meta、Criteo、RTB House、Yahoo | カテゴリマスタとのJOINを確認 |
| `google_product_category` | Google商品カテゴリ | Google、Meta等 | カテゴリコード/名称の対応を確認 |
| `condition` | 商品状態 | Google、Meta、Criteo、RTB House、Yahoo | 値の仕様を確認 |
| `color` | 色 | Google、Meta、Criteo、RTB House、Yahoo | SKU属性か商品属性か確認 |
| `size` | サイズ | Google、Meta、Criteo、RTB House、Yahoo | SKU属性か商品属性か確認 |
| `material` | 素材 | Google、Meta等 | 商品属性テーブルを確認 |
| `gender` | 性別 | Google、Meta等 | デフォルト値と変換ルールを確認 |
| `age_group` | 年齢層 | Google、Meta等 | 固定値かマスタ値か確認 |
| `country_code` | 対象国 | Google等 | 国別配信の有無を確認 |
| `currency_code` | 通貨 | 全チャネル | 税込/税抜とセットで確認 |

## 3. チャネル別項目

### Google Merchant

| 区分 | 項目 |
|---|---|
| 必須候補 | `id`, `title`, `description`, `link`, `image_link`, `availability`, `price` |
| 推奨候補 | `brand`, `google_product_category`, `product_type`, `condition`, `sale_price`, `sale_price_effective_date` |
| 商品属性候補 | `item_group_id`, `color`, `size`, `material`, `gender`, `age_group`, `size_type`, `size_system`, `shipping` |

公式仕様、対象国、価格、配送、GTIN/MPNの扱いを確認して確定します。

### Meta Organic / Dynamic / Collection

| 区分 | 項目 |
|---|---|
| 必須候補 | `id`, `title`, `link`, `image_link`, `availability`, `price` |
| 推奨候補 | `description`, `brand`, `condition`, `sale_price`, `item_group_id`, `product_type` |
| 商品属性候補 | `color`, `size`, `material`, `gender`, `age_group`, `custom_label_*` |

チャネルごとにID加工、UTM、在庫条件、セール条件が異なるか確認します。

### Criteo Catalog（仮マッピング）

| 区分 | 項目 |
|---|---|
| 仮の基本項目 | `id`, `title`, `description`, `category`, `link`, `image_link`, `price`, `availability`, `brand` |
| 仮の推奨項目 | `sale_price`, `gtin`, `mpn`, `item_group_id`, `color`, `size`, `country`, `condition` |

Criteo公式仕様で、フィード形式、項目名、価格表現、在庫値、カテゴリ、更新方法を確認してください。

### RTB House DataFeed（仮マッピング）

| 区分 | 項目 |
|---|---|
| 仮の基本項目 | `id`, `title`, `description`, `link`, `image_link`, `price`, `availability`, `category` |
| 仮の推奨項目 | `brand`, `color`, `size`, `stock_quantity`, `sale_price`, `shipping_cost`, `condition` |

RTB Houseの指定仕様で、CSV/XML等の形式、タグ名/カラム名、文字コード、更新・設置方法を確認してください。

### Yahoo Shopping Ads（仮マッピング）

| 区分 | 項目 |
|---|---|
| 仮の基本項目 | `item_id`, `item_name`, `item_description`, `item_url`, `image_url`, `price`, `availability` |
| 仮の推奨項目 | `brand`, `category`, `color`, `size`, `stock_quantity`, `sale_price`, `gtin`, `jan_code` |

Yahoo広告ヘルプで、対象サービス、フィード種類、正式なカラム名、区切り文字、ヘッダー、文字コード、アップロード方法を確認してください。

## 4. ヒアリングの進め方

1. 連携チャネルを選択する。
2. 選択チャネルの必須候補を一覧化する。
3. 推奨候補を採用するか確認する。
4. 各項目について、DB名・テーブル名・カラム名・型・粒度を確認する。
5. 未確定項目を「要確認」として一覧化する。
6. すべての必須項目とJOINキーが確認できた後にBASE SQLを作成する。
