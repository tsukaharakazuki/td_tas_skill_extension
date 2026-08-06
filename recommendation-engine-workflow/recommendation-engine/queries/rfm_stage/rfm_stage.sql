-- ロジック10: RFM / 顧客ステージ別レコメンド
-- Recency(直近購入) / Frequency(購入回数) / Monetary(購入金額) からステージを判定し、
-- ステージごとに異なる推薦方針（優良顧客への上位商品、休眠層への再購入促進商品）を適用する。

WITH rfm_base AS (
    SELECT
        member_id AS key_value
        , (UNIX_TIMESTAMP() - MAX(time)) / 86400.0 AS recency_days
        , COUNT(DISTINCT order_id) AS frequency
        , SUM(amount) AS monetary
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.rfm_stage.lookback_days}d', 'JST')
    GROUP BY member_id
)
, rfm_scored AS (
    SELECT
        key_value
        , recency_days
        , frequency
        , monetary
        , NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score
        , NTILE(5) OVER (ORDER BY frequency DESC) AS f_score
        , NTILE(5) OVER (ORDER BY monetary DESC) AS m_score
    FROM rfm_base
)
, staged AS (
    SELECT
        key_value
        , CASE
            WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'loyal'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'at_risk'
            WHEN r_score >= 4 AND f_score >= 4 THEN 'dormant'
            ELSE 'regular'
          END AS stage
    FROM rfm_scored
)
, stage_bestseller AS (
    -- ステージ別の売れ筋（loyal/regularは全体トレンド商品、at_risk/dormantは再購入喚起商品として同じ売れ筋を利用）
    SELECT
        product_id
        , SUM(amount) AS total_amount
        , ROW_NUMBER() OVER (ORDER BY SUM(amount) DESC) AS rank_in_logic
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.rfm_stage.lookback_days}d', 'JST')
    GROUP BY product_id
)
, top_products AS (
    SELECT * FROM stage_bestseller WHERE rank_in_logic <= ${logics.rfm_stage.top_n}
)
SELECT
    '${logics.rfm_stage.key_column}' AS key_type
    , s.key_value
    , 'rfm_stage' AS logic_name
    , t.product_id
    , 1.0 / t.rank_in_logic AS score
    , t.rank_in_logic
    , CONCAT('rfm_stage_', s.stage) AS reco_reason
FROM staged s
CROSS JOIN top_products t
