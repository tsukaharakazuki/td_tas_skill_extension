-- ロジック5: カート投入・お気に入りベース
-- 購入直前行動（カート投入・お気に入り登録）を最優先で推薦する。
-- 想定イベント: event_type IN ('cart_add', 'favorite_add')

WITH cart_favorite_products AS (
    SELECT
        ${logics.cart_favorite.key_column} AS key_value
        , product_id
        , event_type
        , MAX(time) AS last_event_at
        , COUNT(*) AS event_count
    FROM ${common.weblog_db}.${common.weblog_tbl}
    WHERE TD_INTERVAL(time, '-${logics.cart_favorite.lookback_days}d', 'JST')
        AND ${logics.cart_favorite.key_column} IS NOT NULL
        AND product_id IS NOT NULL
        AND event_type IN ('cart_add', 'favorite_add')
    GROUP BY ${logics.cart_favorite.key_column}, product_id, event_type
)
, already_purchased AS (
    SELECT DISTINCT
        member_id AS key_value
        , product_id
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.cart_favorite.lookback_days}d', 'JST')
)
, filtered AS (
    SELECT c.*
    FROM cart_favorite_products c
    LEFT JOIN already_purchased p
        ON c.key_value = p.key_value
        AND c.product_id = p.product_id
    WHERE p.product_id IS NULL
)
, ranked AS (
    SELECT
        key_value
        , product_id
        -- カート投入をお気に入りより優先
        , MAX(CASE WHEN event_type = 'cart_add' THEN 2 ELSE 1 END) AS event_weight
        , MAX(last_event_at) AS last_event_at
        , ROW_NUMBER() OVER (
            PARTITION BY key_value
            ORDER BY MAX(CASE WHEN event_type = 'cart_add' THEN 2 ELSE 1 END) DESC, MAX(last_event_at) DESC
          ) AS rank_in_logic
    FROM filtered
    GROUP BY key_value, product_id
)
SELECT
    '${logics.cart_favorite.key_column}' AS key_type
    , key_value
    , 'cart_favorite' AS logic_name
    , product_id
    , event_weight / 2.0 AS score
    , rank_in_logic
    , 'cart_or_favorite' AS reco_reason
FROM ranked
WHERE rank_in_logic <= ${logics.cart_favorite.top_n}
