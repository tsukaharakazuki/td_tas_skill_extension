-- ロジック14: 時間・季節性レコメンド
-- 現在の季節に対応するカテゴリ（config/params.yml の season_categories で設定）の
-- 売れ筋商品を、直近アクティブなユーザーに推薦する。
-- season_category_ids はdigファイル側で現在月から季節を判定し、カンマ区切り文字列として渡す。

WITH seasonal_bestseller AS (
    SELECT
        product_id
        , SUM(amount) AS total_amount
        , ROW_NUMBER() OVER (ORDER BY SUM(amount) DESC) AS rank_in_logic
    FROM ${common.order_db}.${common.order_tbl} o
    JOIN ${common.product_db}.${common.product_tbl} p
        ON o.product_id = p.product_id
    WHERE TD_INTERVAL(o.time, '-${logics.time_seasonality.lookback_days}d', 'JST')
        AND p.category_id IN (${season_category_ids})
    GROUP BY product_id
)
, top_products AS (
    SELECT * FROM seasonal_bestseller WHERE rank_in_logic <= ${logics.time_seasonality.top_n}
)
, active_keys AS (
    SELECT DISTINCT ${logics.time_seasonality.key_column} AS key_value
    FROM ${common.weblog_db}.${common.weblog_tbl}
    WHERE TD_INTERVAL(time, '-30d', 'JST')
        AND ${logics.time_seasonality.key_column} IS NOT NULL
)
SELECT
    '${logics.time_seasonality.key_column}' AS key_type
    , k.key_value
    , 'time_seasonality' AS logic_name
    , t.product_id
    , 1.0 / t.rank_in_logic AS score
    , t.rank_in_logic
    , 'seasonal_bestseller' AS reco_reason
FROM active_keys k
CROSS JOIN top_products t
