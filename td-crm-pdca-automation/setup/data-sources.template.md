# データソースと分析ガイドライン — {{organization.name}}

<!-- SETUP-NOTE: セットアップSkillが config/environment.yml の値で二重波括弧のプレースホルダーをすべて置き換えて生成する。使えないテーブルに依存するセクションは「この環境では利用不可（理由）」に置き換える。生成時にこのコメントは削除する。 -->
> 【分析】【施策】は、SQLを書く前に必ずこのファイルと `config/environment.yml` を読みます。

## 1. 使用テーブル

| 用途 | テーブル | 1行の単位 | 備考 |
|---|---|---|---|
| 顧客（会員） | `{{tables.customer.name}}` | {{tables.customer.grain}} | 顧客ID: `{{columns.customer.customer_id}}` |
| 購買（注文） | `{{tables.purchase.name}}` | {{tables.purchase.grain}} | 注文ID: `{{columns.purchase.order_id}}` |
| Webアクセス | `{{tables.weblog.name}}` | 1ページビュー | セッションID: `{{columns.weblog.session_id}}` |
| 配信結果集計 | {{engage_analytics.tables}} | — | 無い場合はCheck開始時に導入を提案 |

## 2. ID対応

| 用途 | テーブル.カラム | 基準ID（会員ID）への変換 |
|---|---|---|
| 会員 | `{{tables.customer.name}}.{{columns.customer.customer_id}}` | 基準ID |
| 購買 | `{{tables.purchase.name}}.{{columns.purchase.customer_id}}` | {{id_mapping.purchase_to_base}} |
| Web | `{{tables.weblog.name}}.{{columns.weblog.customer_id}}` | {{id_mapping.web_to_base}} |
| 配信 | 配信ツール側の宛先ID | {{id_mapping.delivery_to_base}} |

注文IDの対応（Web購入完了ログ ↔ 購買テーブル）: {{id_mapping.order_id_web_to_purchase}}

補足: {{id_mapping.notes}}

## 3. 分析時の必須ルール

- `time` を持つテーブルは必ず `TD_INTERVAL(time, '<範囲>', '{{organization.timezone}}')` で期間を絞る。
- 売上・購買件数の集計は、必ず有効な注文だけにする: `{{business_rules.valid_order_condition}}`
- 除外顧客: `{{business_rules.excluded_customer_condition}}`
- 金額: `{{columns.purchase.amount}}`（{{organization.currency}}・税{{organization.amount_tax}}）。明細行に注文合計が重複して入る場合（`{{columns.purchase.amount_is_order_total_on_each_line}}`）は `{{business_rules.order_dedupe_key}}` で重複排除してから合計する。
- 配信許諾（メール）: `{{columns.customer.permission.email.column}} = {{columns.customer.permission.email.allowed_value}}`
- 新しいテーブル・カラムを使う場合は、事前に利用者へ確認し、確定したら `config/environment.yml` とこのファイルに追記する。
- `tdx query` を実行する前に、必ずクエリと目的を示して承認を取る。

## 4. ページ判定・流入判定

| 判定 | 条件 |
|---|---|
| 商品詳細ページ | `{{page_rules.product_detail}}` |
| カートページ | `{{page_rules.cart}}` |
| 購入完了ページ | `{{page_rules.purchase_complete}}` |
| 配信経由流入 | `{{inflow_rule}}`（`{campaign}` を施策の識別子に置き換える） |

## 5. 定番SQL

> 下記は `derived_metrics.source = {{derived_metrics.source}}` に合わせて生成します。
> `customer` の場合は顧客マスタの集計済みカラムを、`purchase` の場合は購買データから算出するSQLを残します。

### 5-1. 休眠（最終購入からの経過日数）分布

```sql
WITH last_order AS (
  SELECT
    {{columns.purchase.customer_id}} AS customer_id,
    MAX(time) AS last_time,
    COUNT(DISTINCT {{columns.purchase.order_id}}) AS order_count
  FROM {{tables.purchase.name}}
  WHERE TD_INTERVAL(time, '-1095d', '{{organization.timezone}}')
    AND {{business_rules.valid_order_condition}}
  GROUP BY 1
)
SELECT
  CASE
    WHEN date_diff('day', from_unixtime(last_time), current_timestamp) <= 90  THEN '01: 0-90日'
    WHEN date_diff('day', from_unixtime(last_time), current_timestamp) <= 180 THEN '02: 91-180日'
    WHEN date_diff('day', from_unixtime(last_time), current_timestamp) <= 365 THEN '03: 181-365日'
    ELSE '04: 365日超'
  END AS recency_bucket,
  COUNT(*) AS customers,
  AVG(order_count) AS avg_orders
FROM last_order
GROUP BY 1
ORDER BY 1
```

### 5-2. ブランド（カテゴリ）別の購買者数

```sql
SELECT
  {{columns.purchase.brand}} AS brand,
  COUNT(DISTINCT {{columns.purchase.customer_id}}) AS buyers
FROM {{tables.purchase.name}}
WHERE TD_INTERVAL(time, '-365d', '{{organization.timezone}}')
  AND {{business_rules.valid_order_condition}}
GROUP BY 1
ORDER BY 2 DESC
```

### 5-3. F2転換率（初回購入者のうち2回目購入に至った割合）

```sql
WITH orders AS (
  SELECT
    {{columns.purchase.customer_id}} AS customer_id,
    {{columns.purchase.order_id}} AS order_id,
    MIN(time) AS time
  FROM {{tables.purchase.name}}
  WHERE TD_INTERVAL(time, '-730d', '{{organization.timezone}}')
    AND {{business_rules.valid_order_condition}}
  GROUP BY 1, 2
),
seq AS (
  SELECT customer_id,
         ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY time) AS purchase_seq
  FROM orders
),
base AS (
  SELECT customer_id,
         MAX(CASE WHEN purchase_seq = 1 THEN 1 ELSE 0 END) AS is_f1,
         MAX(CASE WHEN purchase_seq = 2 THEN 1 ELSE 0 END) AS is_f2
  FROM seq
  GROUP BY 1
)
SELECT COUNT(*) AS f1,
       SUM(is_f2) AS f2,
       ROUND(100.0 * SUM(is_f2) / COUNT(*), 2) AS f2_rate_pct
FROM base
WHERE is_f1 = 1
```

> 対象期間より前に購入歴がある顧客も「1回目」と数えてしまうため、正確に測る場合は初回購入日カラム（`{{columns.customer.first_order_date}}`）で初回購入が期間内の顧客に絞る。

### 5-4. 配信経由のサイト流入

```sql
SELECT
  COUNT(DISTINCT {{columns.weblog.session_id}}) AS sessions,
  COUNT(DISTINCT {{columns.weblog.customer_id}}) AS customers
FROM {{tables.weblog.name}}
WHERE TD_INTERVAL(time, '<配信日>/14d', '{{organization.timezone}}')
  AND ({{inflow_rule}})
```

### 5-5. 配信群とコントロール群の購買比較

配信対象リスト（`<segment_table>`：顧客ID と `group` 列＝`treatment` / `control`）がある前提です。

```sql
WITH target AS (
  SELECT customer_id, "group" FROM <segment_table>
),
purchase AS (
  SELECT {{columns.purchase.customer_id}} AS customer_id,
         {{columns.purchase.order_id}} AS order_id,
         {{columns.purchase.amount}} AS amount
  FROM {{tables.purchase.name}}
  WHERE TD_INTERVAL(time, '<配信日>/14d', '{{organization.timezone}}')
    AND {{business_rules.valid_order_condition}}
)
SELECT
  t."group",
  COUNT(DISTINCT t.customer_id) AS targets,
  COUNT(DISTINCT p.customer_id) AS buyers,
  ROUND(100.0 * COUNT(DISTINCT p.customer_id) / COUNT(DISTINCT t.customer_id), 2) AS purchase_rate_pct,
  SUM(p.amount) AS sales
FROM target t
LEFT JOIN purchase p ON t.customer_id = p.customer_id
GROUP BY 1
```

> 明細行に注文合計が重複する環境では、`purchase` CTE で注文IDごとに1行へ集約してから合計する。

## 6. セグメント・配信基盤

- セグメント作成: {{audience.tool}}
- Parent Segment: {{audience.parent_segments}}
- チャネル: {{delivery.channels}}
- 配信ツール: {{delivery.tools}}
- Engage Workspace: {{delivery.engage_workspace}}
- コントロール群: {{delivery.control_group}}
- 配信上限: {{defaults.frequency_cap}}
- 避ける時間帯: {{defaults.avoid_send_windows}}
