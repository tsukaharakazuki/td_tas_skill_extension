-- ML購入確率予測 - 特徴量抽出（学習・推論共通）
-- 観測期間内の会員ごとの行動・購買特徴量を作成する。
-- 実際の特徴量はクライアント要件に応じて拡張すること（本サンプルは型のみ）。

WITH weblog_features AS (
    SELECT
        ${common.id_mapping_tbl}.member_id AS member_id
        , COUNT(*) AS pv_count
        , COUNT(DISTINCT session_id) AS session_count
        , COUNT(DISTINCT category_id) AS distinct_category_count
        , COUNT(DISTINCT brand_id) AS distinct_brand_count
        , AVG(dwell_seconds) AS avg_dwell_seconds
    FROM ${common.weblog_db}.${common.weblog_tbl} w
    JOIN ${common.id_mapping_db}.${common.id_mapping_tbl}
        ON w.cookie = ${common.id_mapping_tbl}.cookie
    WHERE TD_INTERVAL(w.time, '-${logics.ml_purchase_probability.observation_days}d', 'JST')
    GROUP BY ${common.id_mapping_tbl}.member_id
)
, purchase_features AS (
    SELECT
        member_id
        , COUNT(DISTINCT order_id) AS purchase_count
        , SUM(amount) AS total_amount
        , MAX(time) AS last_purchase_time
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.ml_purchase_probability.observation_days}d', 'JST')
    GROUP BY member_id
)
, member_base AS (
    SELECT member_id, gender, age_band, member_rank
    FROM ${common.member_db}.${common.member_tbl}
)
-- DIGDAG_INSERT_LINE
SELECT
    m.member_id
    , m.gender
    , m.age_band
    , m.member_rank
    , COALESCE(w.pv_count, 0) AS pv_count
    , COALESCE(w.session_count, 0) AS session_count
    , COALESCE(w.distinct_category_count, 0) AS distinct_category_count
    , COALESCE(w.distinct_brand_count, 0) AS distinct_brand_count
    , COALESCE(w.avg_dwell_seconds, 0) AS avg_dwell_seconds
    , COALESCE(p.purchase_count, 0) AS purchase_count
    , COALESCE(p.total_amount, 0) AS total_amount
    , p.last_purchase_time
FROM member_base m
LEFT JOIN weblog_features w ON m.member_id = w.member_id
LEFT JOIN purchase_features p ON m.member_id = p.member_id
