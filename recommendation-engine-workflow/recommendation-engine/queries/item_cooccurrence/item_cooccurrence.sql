-- ロジック7: 商品間協調フィルタリング（アイテムベースCF）
-- 「この商品を買った/見た人はこんな商品も」形式の共起関係を購買+閲覧ログから算出する。

WITH user_product_events AS (
    -- 購買行動
    SELECT member_id AS key_value, product_id, time
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.item_cooccurrence.lookback_days}d', 'JST')

    UNION ALL

    -- 閲覧行動
    SELECT ${logics.item_cooccurrence.key_column} AS key_value, product_id, time
    FROM ${common.weblog_db}.${common.weblog_tbl}
    WHERE TD_INTERVAL(time, '-${logics.item_cooccurrence.lookback_days}d', 'JST')
        AND ${logics.item_cooccurrence.key_column} IS NOT NULL
        AND product_id IS NOT NULL
)
, cooccurrence_pairs AS (
    SELECT
        a.product_id AS base_product_id
        , b.product_id AS reco_product_id
        , COUNT(DISTINCT a.key_value) AS cooccurrence_count
    FROM user_product_events a
    JOIN user_product_events b
        ON a.key_value = b.key_value
        AND a.product_id != b.product_id
    GROUP BY a.product_id, b.product_id
    HAVING COUNT(DISTINCT a.key_value) >= ${logics.item_cooccurrence.min_cooccurrence_count}
)
, ranked_pairs AS (
    SELECT
        base_product_id
        , reco_product_id
        , cooccurrence_count
        , ROW_NUMBER() OVER (
            PARTITION BY base_product_id
            ORDER BY cooccurrence_count DESC
          ) AS rank_within_base
    FROM cooccurrence_pairs
)
, user_recent_products AS (
    SELECT DISTINCT
        key_value
        , product_id AS base_product_id
        , time
    FROM user_product_events
)
, latest_per_user_product AS (
    SELECT
        key_value
        , base_product_id
        , MAX(time) AS last_time
    FROM user_recent_products
    GROUP BY key_value, base_product_id
)
, expanded AS (
    SELECT
        u.key_value
        , p.reco_product_id AS product_id
        , p.cooccurrence_count
        , u.last_time
        , p.rank_within_base
    FROM latest_per_user_product u
    JOIN ranked_pairs p
        ON u.base_product_id = p.base_product_id
    WHERE p.rank_within_base <= 5
)
, ranked AS (
    SELECT
        key_value
        , product_id
        , MAX(cooccurrence_count) AS best_cooccurrence_count
        , ROW_NUMBER() OVER (
            PARTITION BY key_value
            ORDER BY MAX(cooccurrence_count) DESC, MAX(last_time) DESC
          ) AS rank_in_logic
    FROM expanded
    GROUP BY key_value, product_id
)
SELECT
    '${logics.item_cooccurrence.key_column}' AS key_type
    , key_value
    , 'item_cooccurrence' AS logic_name
    , product_id
    , 1.0 / rank_in_logic AS score
    , rank_in_logic
    , 'bought_viewed_together' AS reco_reason
FROM ranked
WHERE rank_in_logic <= ${logics.item_cooccurrence.top_n}
