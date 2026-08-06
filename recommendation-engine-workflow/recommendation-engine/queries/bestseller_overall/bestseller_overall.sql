-- ロジック1: 全体売れ筋（時間減衰つき）
-- アクティブな全ユーザーに対して同一の売れ筋トップNを付与するフォールバックロジック。

WITH scored_products AS (
    SELECT
        product_id
        , SUM(
            amount * POWER(0.5, (UNIX_TIMESTAMP() - time) / (${logics.bestseller_overall.half_life_days} * 86400.0))
          ) AS decayed_score
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.bestseller_overall.lookback_days}d', 'JST')
    GROUP BY product_id
)
, ranked AS (
    SELECT
        product_id
        , decayed_score
        , ROW_NUMBER() OVER (ORDER BY decayed_score DESC) AS rank_in_logic
    FROM scored_products
)
, top_products AS (
    SELECT * FROM ranked WHERE rank_in_logic <= ${logics.bestseller_overall.top_n}
)
, active_keys AS (
    SELECT DISTINCT ${logics.bestseller_overall.key_column} AS key_value
    FROM ${common.weblog_db}.${common.weblog_tbl}
    WHERE TD_INTERVAL(time, '-${logics.bestseller_overall.lookback_days}d', 'JST')
        AND ${logics.bestseller_overall.key_column} IS NOT NULL
)
SELECT
    '${logics.bestseller_overall.key_column}' AS key_type
    , k.key_value
    , 'bestseller_overall' AS logic_name
    , t.product_id
    , t.decayed_score / (SELECT MAX(decayed_score) FROM top_products) AS score
    , t.rank_in_logic
    , 'overall_bestseller' AS reco_reason
FROM active_keys k
CROSS JOIN top_products t
