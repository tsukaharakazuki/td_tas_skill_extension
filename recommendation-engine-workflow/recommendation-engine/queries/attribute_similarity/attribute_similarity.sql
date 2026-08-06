-- ロジック13: 商品属性ベースの類似レコメンド（代替商品）
-- 直近閲覧・購入した商品（基準商品）に対し、商品マスタの属性（カテゴリ/ブランド/
-- 性別ターゲット/価格帯）が近い「代替商品」を推薦する。
-- mode: substitute のみ実装（complementary補完商品はカテゴリ相性マスタが別途必要なため対象外）。

WITH base_products AS (
    -- 直近閲覧または購入した商品を基準商品とする
    SELECT
        ${logics.attribute_similarity.key_column} AS key_value
        , product_id AS base_product_id
        , MAX(time) AS last_touched_at
    FROM ${common.weblog_db}.${common.weblog_tbl}
    WHERE TD_INTERVAL(time, '-${logics.attribute_similarity.lookback_days}d', 'JST')
        AND ${logics.attribute_similarity.key_column} IS NOT NULL
        AND product_id IS NOT NULL
    GROUP BY ${logics.attribute_similarity.key_column}, product_id
)
, ranked_base AS (
    SELECT
        key_value
        , base_product_id
        , ROW_NUMBER() OVER (
            PARTITION BY key_value
            ORDER BY last_touched_at DESC
          ) AS base_rank
    FROM base_products
)
, top_base AS (
    -- 直近3商品を基準に類似商品を展開する
    SELECT * FROM ranked_base WHERE base_rank <= 3
)
, base_with_attrs AS (
    SELECT
        b.key_value
        , b.base_product_id
        , p.category_id
        , p.brand_id
        , p.price
        , p.gender_target
    FROM top_base b
    JOIN ${common.product_db}.${common.product_tbl} p
        ON b.base_product_id = p.product_id
)
, candidate_pairs AS (
    SELECT
        b.key_value
        , b.base_product_id
        , c.product_id AS candidate_product_id
        , (
            CASE WHEN b.category_id = c.category_id THEN 0.4 ELSE 0.0 END
            + CASE WHEN b.brand_id = c.brand_id THEN 0.3 ELSE 0.0 END
            + CASE WHEN b.gender_target = c.gender_target THEN 0.1 ELSE 0.0 END
            + CASE
                WHEN ABS(c.price - b.price) / b.price <= ${logics.attribute_similarity.price_band_tolerance}
                THEN 0.2 ELSE 0.0
              END
          ) AS similarity_score
    FROM base_with_attrs b
    JOIN ${common.product_db}.${common.product_tbl} c
        ON b.category_id = c.category_id
        AND b.base_product_id != c.product_id
)
, already_purchased AS (
    SELECT DISTINCT member_id AS key_value, product_id
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.attribute_similarity.lookback_days}d', 'JST')
)
, filtered AS (
    SELECT c.key_value, c.candidate_product_id, c.similarity_score
    FROM candidate_pairs c
    LEFT JOIN already_purchased a
        ON c.key_value = a.key_value
        AND c.candidate_product_id = a.product_id
    WHERE a.product_id IS NULL
        AND c.similarity_score > 0
)
, ranked AS (
    SELECT
        key_value
        , candidate_product_id AS product_id
        , MAX(similarity_score) AS best_similarity_score
        , ROW_NUMBER() OVER (
            PARTITION BY key_value
            ORDER BY MAX(similarity_score) DESC
          ) AS rank_in_logic
    FROM filtered
    GROUP BY key_value, candidate_product_id
)
SELECT
    '${logics.attribute_similarity.key_column}' AS key_type
    , key_value
    , 'attribute_similarity' AS logic_name
    , product_id
    , best_similarity_score AS score
    , rank_in_logic
    , 'similar_attribute_substitute' AS reco_reason
FROM ranked
WHERE rank_in_logic <= ${logics.attribute_similarity.top_n}
