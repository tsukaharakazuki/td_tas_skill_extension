-- ロジック15: マルチアームド・バンディット（Epsilon-Greedy）
-- 表示・クリック・カート・購入ログ（impression_db.impression_tbl）から商品ごとの
-- 成果率を集計し、活用アーム（実績のある商品）を(1-epsilon)、
-- 探索アーム（表示回数が少ない商品）をepsilonの比率で組み合わせて候補を生成する。
--
-- 前提: impression_tbl のカラムは time, product_id, event_type
--       (event_type IN ('impression','click','cart','purchase'))
-- 十分な表示・成果ログが蓄積されるまでは enabled: false のままにしておくこと。

WITH product_stats AS (
    SELECT
        product_id
        , SUM(CASE WHEN event_type = 'impression' THEN 1 ELSE 0 END) AS impression_count
        , SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS purchase_count
    FROM ${logics.bandit_optimization.impression_db}.${logics.bandit_optimization.impression_tbl}
    WHERE TD_INTERVAL(time, '-${logics.bandit_optimization.lookback_days}d', 'JST')
    GROUP BY product_id
)
, scored AS (
    SELECT
        product_id
        , impression_count
        , purchase_count
        , purchase_count * 1.0 / GREATEST(impression_count, 1) AS conversion_rate
    FROM product_stats
)
, exploit_arms AS (
    -- 活用アーム: 表示回数が十分にあり、成果率で評価できる商品
    SELECT
        product_id
        , conversion_rate AS arm_score
        , 'exploit' AS arm_type
        , ROW_NUMBER() OVER (ORDER BY conversion_rate DESC) AS rank_in_arm
    FROM scored
    WHERE impression_count >= ${logics.bandit_optimization.min_impressions}
)
, explore_arms AS (
    -- 探索アーム: 表示回数が少ない商品（新商品・未評価商品）からランダムに選ぶ
    SELECT
        product_id
        , RAND() AS arm_score
        , 'explore' AS arm_type
        , ROW_NUMBER() OVER (ORDER BY RAND()) AS rank_in_arm
    FROM scored
    WHERE impression_count < ${logics.bandit_optimization.min_impressions}
)
, combined_arms AS (
    SELECT product_id, arm_score, arm_type, rank_in_arm
    FROM exploit_arms
    WHERE rank_in_arm <= CEIL(${logics.bandit_optimization.top_n} * (1 - ${logics.bandit_optimization.epsilon}))

    UNION ALL

    SELECT product_id, arm_score, arm_type, rank_in_arm
    FROM explore_arms
    WHERE rank_in_arm <= CEIL(${logics.bandit_optimization.top_n} * ${logics.bandit_optimization.epsilon})
)
, ranked_arms AS (
    SELECT
        product_id
        , arm_score
        , arm_type
        , ROW_NUMBER() OVER (ORDER BY CASE WHEN arm_type = 'exploit' THEN 0 ELSE 1 END, arm_score DESC) AS rank_in_logic
    FROM combined_arms
)
, active_keys AS (
    SELECT DISTINCT ${logics.bandit_optimization.key_column} AS key_value
    FROM ${common.weblog_db}.${common.weblog_tbl}
    WHERE TD_INTERVAL(time, '-30d', 'JST')
        AND ${logics.bandit_optimization.key_column} IS NOT NULL
)
SELECT
    '${logics.bandit_optimization.key_column}' AS key_type
    , k.key_value
    , 'bandit_optimization' AS logic_name
    , a.product_id
    , CASE WHEN a.arm_type = 'exploit' THEN GREATEST(a.arm_score, 0.01) ELSE 0.01 END AS score
    , a.rank_in_logic
    , CONCAT('bandit_', a.arm_type) AS reco_reason
FROM active_keys k
CROSS JOIN ranked_arms a
WHERE a.rank_in_logic <= ${logics.bandit_optimization.top_n}
