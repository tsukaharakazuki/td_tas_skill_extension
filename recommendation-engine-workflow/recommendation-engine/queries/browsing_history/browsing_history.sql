-- ロジック4: 閲覧履歴ベース
-- 直近見た商品・繰り返し閲覧している商品を推薦する（cookie単位が既定）。

WITH viewed_products AS (
    SELECT
        ${logics.browsing_history.key_column} AS key_value
        , product_id
        , COUNT(*) AS view_count
        , MAX(time) AS last_viewed_at
    FROM ${common.weblog_db}.${common.weblog_tbl}
    WHERE TD_INTERVAL(time, '-${logics.browsing_history.lookback_days}d', 'JST')
        AND ${logics.browsing_history.key_column} IS NOT NULL
        AND product_id IS NOT NULL
        AND event_type IN ('view', 'pageview')
    GROUP BY ${logics.browsing_history.key_column}, product_id
)
, ranked AS (
    SELECT
        key_value
        , product_id
        , view_count
        , last_viewed_at
        , ROW_NUMBER() OVER (
            PARTITION BY key_value
            ORDER BY view_count DESC, last_viewed_at DESC
          ) AS rank_in_logic
    FROM viewed_products
)
SELECT
    '${logics.browsing_history.key_column}' AS key_type
    , key_value
    , 'browsing_history' AS logic_name
    , product_id
    , 1.0 / rank_in_logic AS score
    , rank_in_logic
    , 'recently_viewed' AS reco_reason
FROM ranked
WHERE rank_in_logic <= ${logics.browsing_history.top_n}
