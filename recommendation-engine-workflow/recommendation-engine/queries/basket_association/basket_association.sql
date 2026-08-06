-- ロジック8: 購買バスケット分析（アソシエーション分析）
-- 同一注文（バスケット）内の商品ペアから support / confidence / lift を算出し、
-- リフト値の高い「一緒に買われやすい」商品を推薦する。

WITH basket_items AS (
    SELECT DISTINCT order_id, product_id, member_id
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.basket_association.lookback_days}d', 'JST')
)
, total_baskets AS (
    SELECT COUNT(DISTINCT order_id) AS basket_count
    FROM basket_items
)
, item_support AS (
    SELECT
        product_id
        , COUNT(DISTINCT order_id) AS item_basket_count
    FROM basket_items
    GROUP BY product_id
)
, pair_support AS (
    SELECT
        a.product_id AS base_product_id
        , b.product_id AS assoc_product_id
        , COUNT(DISTINCT a.order_id) AS pair_basket_count
    FROM basket_items a
    JOIN basket_items b
        ON a.order_id = b.order_id
        AND a.product_id != b.product_id
    GROUP BY a.product_id, b.product_id
    HAVING COUNT(DISTINCT a.order_id) >= ${logics.basket_association.min_support_count}
)
, metrics AS (
    SELECT
        p.base_product_id
        , p.assoc_product_id
        , p.pair_basket_count
        , (p.pair_basket_count * 1.0 / t.basket_count) AS support
        , (p.pair_basket_count * 1.0 / s.item_basket_count) AS confidence
        , (p.pair_basket_count * 1.0 / t.basket_count) / (
            (s.item_basket_count * 1.0 / t.basket_count) * (s2.item_basket_count * 1.0 / t.basket_count)
          ) AS lift
    FROM pair_support p
    CROSS JOIN total_baskets t
    JOIN item_support s ON p.base_product_id = s.product_id
    JOIN item_support s2 ON p.assoc_product_id = s2.product_id
    WHERE (p.pair_basket_count * 1.0 / t.basket_count) / (
            (s.item_basket_count * 1.0 / t.basket_count) * (s2.item_basket_count * 1.0 / t.basket_count)
          ) >= ${logics.basket_association.min_lift}
)
, latest_user_products AS (
    SELECT DISTINCT member_id AS key_value, product_id AS base_product_id
    FROM basket_items
)
, expanded AS (
    SELECT
        u.key_value
        , m.assoc_product_id AS product_id
        , m.lift
    FROM latest_user_products u
    JOIN metrics m
        ON u.base_product_id = m.base_product_id
)
, ranked AS (
    SELECT
        key_value
        , product_id
        , MAX(lift) AS best_lift
        , ROW_NUMBER() OVER (
            PARTITION BY key_value
            ORDER BY MAX(lift) DESC
          ) AS rank_in_logic
    FROM expanded
    GROUP BY key_value, product_id
)
SELECT
    '${logics.basket_association.key_column}' AS key_type
    , key_value
    , 'basket_association' AS logic_name
    , product_id
    , best_lift / (SELECT MAX(best_lift) FROM ranked) AS score
    , rank_in_logic
    , 'basket_association' AS reco_reason
FROM ranked
WHERE rank_in_logic <= ${logics.basket_association.top_n}
