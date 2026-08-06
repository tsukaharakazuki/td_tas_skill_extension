-- ロジック9: 属性フィット
-- 年代・性別・価格帯とカテゴリ人気の組み合わせから、似た属性を持つ他ユーザーの
-- 購買傾向をもとに商品を推薦する（新規/データ不足ユーザーへのパーソナライズに有効）。

WITH member_attributes AS (
    SELECT member_id, gender, age_band
    FROM ${common.member_db}.${common.member_tbl}
)
, segment_purchases AS (
    SELECT
        m.gender
        , m.age_band
        , o.product_id
        , SUM(o.amount) AS total_amount
    FROM ${common.order_db}.${common.order_tbl} o
    JOIN member_attributes m
        ON o.member_id = m.member_id
    WHERE TD_INTERVAL(o.time, '-${logics.attribute_fit.lookback_days}d', 'JST')
    GROUP BY m.gender, m.age_band, o.product_id
)
, ranked_by_segment AS (
    SELECT
        gender
        , age_band
        , product_id
        , total_amount
        , ROW_NUMBER() OVER (
            PARTITION BY gender, age_band
            ORDER BY total_amount DESC
          ) AS rank_in_segment
    FROM segment_purchases
)
, already_purchased AS (
    SELECT DISTINCT member_id, product_id
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.attribute_fit.lookback_days}d', 'JST')
)
, joined AS (
    SELECT
        m.member_id AS key_value
        , r.product_id
        , r.total_amount
        , r.rank_in_segment
    FROM member_attributes m
    JOIN ranked_by_segment r
        ON m.gender = r.gender
        AND m.age_band = r.age_band
    LEFT JOIN already_purchased p
        ON m.member_id = p.member_id
        AND r.product_id = p.product_id
    WHERE r.rank_in_segment <= ${logics.attribute_fit.top_n}
        AND p.product_id IS NULL
)
SELECT
    '${logics.attribute_fit.key_column}' AS key_type
    , key_value
    , 'attribute_fit' AS logic_name
    , product_id
    , 1.0 / rank_in_segment AS score
    , rank_in_segment AS rank_in_logic
    , 'attribute_segment_fit' AS reco_reason
FROM joined
