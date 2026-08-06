-- ロジック3: ブランド別売れ筋
-- 閲覧・購入ブランドへの関心度に応じてパーソナライズしたブランド内売れ筋を推薦する。

WITH user_brand_interest AS (
    SELECT
        ${logics.bestseller_brand.key_column} AS key_value
        , brand_id
        , COUNT(*) AS interest_score
        , ROW_NUMBER() OVER (
            PARTITION BY ${logics.bestseller_brand.key_column}
            ORDER BY COUNT(*) DESC
          ) AS brand_rank
    FROM ${common.weblog_db}.${common.weblog_tbl}
    WHERE TD_INTERVAL(time, '-${logics.bestseller_brand.lookback_days}d', 'JST')
        AND ${logics.bestseller_brand.key_column} IS NOT NULL
        AND brand_id IS NOT NULL
    GROUP BY ${logics.bestseller_brand.key_column}, brand_id
)
, brand_bestseller AS (
    SELECT
        brand_id
        , product_id
        , SUM(amount) AS total_amount
        , ROW_NUMBER() OVER (
            PARTITION BY brand_id
            ORDER BY SUM(amount) DESC
          ) AS rank_in_brand
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.bestseller_brand.lookback_days}d', 'JST')
    GROUP BY brand_id, product_id
)
, joined AS (
    SELECT
        u.key_value
        , b.product_id
        , b.total_amount
        , ROW_NUMBER() OVER (
            PARTITION BY u.key_value
            ORDER BY b.total_amount DESC
          ) AS rank_in_logic
    FROM user_brand_interest u
    JOIN brand_bestseller b
        ON u.brand_id = b.brand_id
    WHERE u.brand_rank <= 3
        AND b.rank_in_brand <= ${logics.bestseller_brand.top_n}
)
SELECT
    '${logics.bestseller_brand.key_column}' AS key_type
    , key_value
    , 'bestseller_brand' AS logic_name
    , product_id
    , 1.0 / rank_in_logic AS score
    , rank_in_logic
    , 'brand_bestseller' AS reco_reason
FROM joined
WHERE rank_in_logic <= ${logics.bestseller_brand.top_n}
