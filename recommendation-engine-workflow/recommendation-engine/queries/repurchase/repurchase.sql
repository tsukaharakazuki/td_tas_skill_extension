-- ロジック6: 再購入予測
-- 過去の購入周期（平均購入間隔）から、次回購入タイミングが近い商品を推薦する。
-- 周期計算には最低 min_purchase_count 回の購入履歴が必要。

WITH purchase_history AS (
    SELECT
        member_id AS key_value
        , product_id
        , time
        , LAG(time) OVER (
            PARTITION BY member_id, product_id
            ORDER BY time
          ) AS prev_time
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.repurchase.lookback_days}d', 'JST')
)
, intervals AS (
    SELECT
        key_value
        , product_id
        , (time - prev_time) / 86400.0 AS interval_days
        , time AS purchase_time
    FROM purchase_history
    WHERE prev_time IS NOT NULL
)
, purchase_stats AS (
    SELECT
        key_value
        , product_id
        , AVG(interval_days) AS avg_interval_days
        , COUNT(*) + 1 AS purchase_count
        , MAX(purchase_time) AS last_purchase_time
    FROM intervals
    GROUP BY key_value, product_id
    HAVING COUNT(*) + 1 >= ${logics.repurchase.min_purchase_count}
)
, due_products AS (
    SELECT
        key_value
        , product_id
        , avg_interval_days
        , last_purchase_time
        -- 「次回購入予定日」までの残り日数（負値ほど購入タイミングが近い/過ぎている）
        , (UNIX_TIMESTAMP() - last_purchase_time) / 86400.0 - avg_interval_days AS days_past_due
    FROM purchase_stats
)
, ranked AS (
    SELECT
        key_value
        , product_id
        , days_past_due
        , ROW_NUMBER() OVER (
            PARTITION BY key_value
            ORDER BY days_past_due DESC
          ) AS rank_in_logic
    FROM due_products
    -- 予定日の前後一定期間内（早すぎる再購入提案を避けるため過去-30日以内は除外しない）
    WHERE days_past_due > -30
)
SELECT
    '${logics.repurchase.key_column}' AS key_type
    , key_value
    , 'repurchase' AS logic_name
    , product_id
    , 1.0 / rank_in_logic AS score
    , rank_in_logic
    , 'repurchase_timing' AS reco_reason
FROM ranked
WHERE rank_in_logic <= ${logics.repurchase.top_n}
