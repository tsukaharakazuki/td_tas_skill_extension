-- ロジック2: カテゴリ別売れ筋
-- 各ユーザーの直近閲覧カテゴリ上位に対して、そのカテゴリの売れ筋商品を推薦する。

WITH user_top_categories AS (
    SELECT
        ${logics.bestseller_category.key_column} AS key_value
        , category_id
        , COUNT(*) AS view_count
        , ROW_NUMBER() OVER (
            PARTITION BY ${logics.bestseller_category.key_column}
            ORDER BY COUNT(*) DESC
          ) AS category_rank
    FROM ${common.weblog_db}.${common.weblog_tbl}
    WHERE TD_INTERVAL(time, '-${logics.bestseller_category.lookback_days}d', 'JST')
        AND ${logics.bestseller_category.key_column} IS NOT NULL
        AND category_id IS NOT NULL
    GROUP BY ${logics.bestseller_category.key_column}, category_id
)
, category_bestseller AS (
    SELECT
        category_id
        , product_id
        , SUM(amount) AS total_amount
        , ROW_NUMBER() OVER (
            PARTITION BY category_id
            ORDER BY SUM(amount) DESC
          ) AS rank_in_category
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.bestseller_category.lookback_days}d', 'JST')
    GROUP BY category_id, product_id
)
, joined AS (
    SELECT
        u.key_value
        , c.product_id
        , c.total_amount
        , ROW_NUMBER() OVER (
            PARTITION BY u.key_value
            ORDER BY c.total_amount DESC
          ) AS rank_in_logic
    FROM user_top_categories u
    JOIN category_bestseller c
        ON u.category_id = c.category_id
    WHERE u.category_rank <= 3
        AND c.rank_in_category <= ${logics.bestseller_category.top_n}
)
SELECT
    '${logics.bestseller_category.key_column}' AS key_type
    , key_value
    , 'bestseller_category' AS logic_name
    , product_id
    , 1.0 / rank_in_logic AS score
    , rank_in_logic
    , 'category_bestseller' AS reco_reason
FROM joined
WHERE rank_in_logic <= ${logics.bestseller_category.top_n}
