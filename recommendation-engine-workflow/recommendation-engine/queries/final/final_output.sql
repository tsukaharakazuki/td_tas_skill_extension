-- 最終統合ロジック
-- 全ロジックの候補（reco_all_candidates）を正規化・重み付け・多様性制約適用のうえ
-- ユーザーごとの最終レコメンドリストを作成する。
--
-- 注意: 多様性制約（max_per_category / max_per_brand）は、カテゴリ/ブランドごとの
-- ROW_NUMBER上限フィルタによる近似実装。厳密な逐次選択ロジックが必要な場合は
-- py>オペレータでの後処理に置き換えること。

WITH weights AS (
    -- ロジックごとの重み（config/params.yml の final.weights を展開）
    SELECT 'bestseller_overall' AS logic_name, CAST(${final.weights.bestseller_overall} AS DOUBLE) AS weight
    UNION ALL SELECT 'bestseller_category', CAST(${final.weights.bestseller_category} AS DOUBLE)
    UNION ALL SELECT 'bestseller_brand', CAST(${final.weights.bestseller_brand} AS DOUBLE)
    UNION ALL SELECT 'browsing_history', CAST(${final.weights.browsing_history} AS DOUBLE)
    UNION ALL SELECT 'cart_favorite', CAST(${final.weights.cart_favorite} AS DOUBLE)
    UNION ALL SELECT 'repurchase', CAST(${final.weights.repurchase} AS DOUBLE)
    UNION ALL SELECT 'item_cooccurrence', CAST(${final.weights.item_cooccurrence} AS DOUBLE)
    UNION ALL SELECT 'basket_association', CAST(${final.weights.basket_association} AS DOUBLE)
    UNION ALL SELECT 'attribute_fit', CAST(${final.weights.attribute_fit} AS DOUBLE)
    UNION ALL SELECT 'rfm_stage', CAST(${final.weights.rfm_stage} AS DOUBLE)
    UNION ALL SELECT 'ml_purchase_probability', CAST(${final.weights.ml_purchase_probability} AS DOUBLE)
    UNION ALL SELECT 'user_based_cf', CAST(${final.weights.user_based_cf} AS DOUBLE)
    UNION ALL SELECT 'attribute_similarity', CAST(${final.weights.attribute_similarity} AS DOUBLE)
    UNION ALL SELECT 'time_seasonality', CAST(${final.weights.time_seasonality} AS DOUBLE)
    UNION ALL SELECT 'bandit_optimization', CAST(${final.weights.bandit_optimization} AS DOUBLE)
)
, normalized AS (
    -- ロジック内でmin-max正規化してから重みを掛け合わせる（ロジック間のスコアスケール差を吸収）
    SELECT
        c.key_type
        , c.key_value
        , c.logic_name
        , c.product_id
        , c.reco_reason
        , (c.score - MIN(c.score) OVER (PARTITION BY c.logic_name)) /
          GREATEST(
            MAX(c.score) OVER (PARTITION BY c.logic_name) - MIN(c.score) OVER (PARTITION BY c.logic_name),
            0.000001
          ) AS normalized_score
        , w.weight
    FROM reco_all_candidates c
    JOIN weights w ON c.logic_name = w.logic_name
)
, weighted AS (
    SELECT
        key_type
        , key_value
        , logic_name
        , product_id
        , reco_reason
        , normalized_score * weight AS weighted_score
    FROM normalized
)
-- 同一ユーザー×商品が複数ロジックから候補に挙がった場合は、最も重み付けスコアの高いロジックを採用
, deduped AS (
    SELECT
        key_type
        , key_value
        , product_id
        , logic_name
        , reco_reason
        , weighted_score
        , ROW_NUMBER() OVER (
            PARTITION BY key_value, product_id
            ORDER BY weighted_score DESC
          ) AS dedup_rank
    FROM weighted
)
, dedup_filtered AS (
    SELECT key_type, key_value, product_id, logic_name, reco_reason, weighted_score
    FROM deduped
    WHERE dedup_rank = 1
)
-- 在庫切れ・販売終了商品の除外
, product_filtered AS (
    SELECT
        d.*
        , p.category_id
        , p.brand_id
    FROM dedup_filtered d
    JOIN ${common.product_db}.${common.product_tbl} p
        ON d.product_id = p.product_id
    WHERE (
        ${final.exclude_out_of_stock} = false
        OR (p.sale_status = 'on_sale' AND p.stock_qty > 0)
      )
)
-- 直近購入済み商品の除外（exclude_purchased_within_days > 0の場合のみ有効）
, recently_purchased AS (
    SELECT DISTINCT member_id AS key_value, product_id
    FROM ${common.order_db}.${common.order_tbl}
    WHERE ${final.exclude_purchased_within_days} > 0
        AND TD_INTERVAL(time, '-${final.exclude_purchased_within_days}d', 'JST')
)
, purchase_filtered AS (
    SELECT f.*
    FROM product_filtered f
    LEFT JOIN recently_purchased r
        ON f.key_value = r.key_value
        AND f.product_id = r.product_id
    WHERE r.product_id IS NULL
)
-- 多様性制約: カテゴリ/ブランドごとの採用上限を超える候補を除外（近似実装）
, diversity_ranked AS (
    SELECT
        *
        , ROW_NUMBER() OVER (
            PARTITION BY key_value, category_id
            ORDER BY weighted_score DESC
          ) AS category_rank
        , ROW_NUMBER() OVER (
            PARTITION BY key_value, brand_id
            ORDER BY weighted_score DESC
          ) AS brand_rank
    FROM purchase_filtered
)
, diversity_filtered AS (
    SELECT *
    FROM diversity_ranked
    WHERE category_rank <= ${final.max_per_category}
        AND brand_rank <= ${final.max_per_brand}
)
, final_ranked AS (
    SELECT
        *
        , ROW_NUMBER() OVER (
            PARTITION BY key_value
            ORDER BY weighted_score DESC
          ) AS final_rank
    FROM diversity_filtered
)
SELECT
    key_type
    , key_value
    , final_rank
    , product_id
    , category_id
    , brand_id
    , logic_name AS adopted_logic
    , reco_reason
    , weighted_score
FROM final_ranked
WHERE final_rank <= ${final.top_n_per_user}
