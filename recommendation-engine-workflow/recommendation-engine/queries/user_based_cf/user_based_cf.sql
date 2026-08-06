-- ロジック12: ユーザー間協調フィルタリング
-- 購入商品の重なりが多い「類似ユーザー」を見つけ、類似ユーザーが購入済み・
-- 対象ユーザーが未購入の商品を推薦する。
-- 類似度は共通購入商品数（簡易Jaccard近似）で判定する。

WITH user_products AS (
    SELECT DISTINCT
        member_id AS key_value
        , product_id
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.user_based_cf.lookback_days}d', 'JST')
)
, user_product_count AS (
    SELECT key_value, COUNT(*) AS product_count
    FROM user_products
    GROUP BY key_value
)
, common_products AS (
    SELECT
        a.key_value AS target_user
        , b.key_value AS similar_user
        , COUNT(*) AS common_product_count
    FROM user_products a
    JOIN user_products b
        ON a.product_id = b.product_id
        AND a.key_value != b.key_value
    GROUP BY a.key_value, b.key_value
    HAVING COUNT(*) >= ${logics.user_based_cf.min_common_products}
)
, similarity AS (
    -- Jaccard近似: 共通購入商品数 ÷ (対象ユーザーの購入商品数 + 類似ユーザーの購入商品数 - 共通購入商品数)
    SELECT
        c.target_user
        , c.similar_user
        , c.common_product_count
        , c.common_product_count * 1.0 / (
            t.product_count + s.product_count - c.common_product_count
          ) AS jaccard_similarity
    FROM common_products c
    JOIN user_product_count t ON c.target_user = t.key_value
    JOIN user_product_count s ON c.similar_user = s.key_value
)
, ranked_similar_users AS (
    SELECT
        target_user
        , similar_user
        , jaccard_similarity
        , ROW_NUMBER() OVER (
            PARTITION BY target_user
            ORDER BY jaccard_similarity DESC
          ) AS similarity_rank
    FROM similarity
)
, top_similar_users AS (
    SELECT * FROM ranked_similar_users
    WHERE similarity_rank <= ${logics.user_based_cf.max_similar_users}
)
, candidate_products AS (
    SELECT
        u.target_user AS key_value
        , p.product_id
        , SUM(u.jaccard_similarity) AS total_similarity_score
    FROM top_similar_users u
    JOIN user_products p
        ON u.similar_user = p.key_value
    LEFT JOIN user_products own
        ON u.target_user = own.key_value
        AND p.product_id = own.product_id
    WHERE own.product_id IS NULL
    GROUP BY u.target_user, p.product_id
)
, ranked AS (
    SELECT
        key_value
        , product_id
        , total_similarity_score
        , ROW_NUMBER() OVER (
            PARTITION BY key_value
            ORDER BY total_similarity_score DESC
          ) AS rank_in_logic
    FROM candidate_products
)
SELECT
    '${logics.user_based_cf.key_column}' AS key_type
    , key_value
    , 'user_based_cf' AS logic_name
    , product_id
    , total_similarity_score / (SELECT MAX(total_similarity_score) FROM ranked) AS score
    , rank_in_logic
    , 'similar_user_purchased' AS reco_reason
FROM ranked
WHERE rank_in_logic <= ${logics.user_based_cf.top_n}
