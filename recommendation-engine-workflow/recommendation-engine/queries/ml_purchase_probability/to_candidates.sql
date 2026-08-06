-- ML購入確率予測 - 推論結果を候補レコメンドに変換
-- tasks/ml_purchase_probability の Python推論が書き込む
-- ${common.database}.ml_purchase_probability_scores (member_id, category_id, purchase_probability)
-- を、カテゴリ内売れ筋商品と組み合わせて候補商品リストに変換する。

WITH category_bestseller AS (
    SELECT
        category_id
        , product_id
        , ROW_NUMBER() OVER (
            PARTITION BY category_id
            ORDER BY SUM(amount) DESC
          ) AS rank_in_category
    FROM ${common.order_db}.${common.order_tbl}
    WHERE TD_INTERVAL(time, '-${logics.ml_purchase_probability.observation_days}d', 'JST')
    GROUP BY category_id, product_id
)
, top_category_products AS (
    SELECT * FROM category_bestseller WHERE rank_in_category <= 3
)
, scored AS (
    SELECT
        member_id AS key_value
        , category_id
        , purchase_probability
        , ROW_NUMBER() OVER (
            PARTITION BY member_id
            ORDER BY purchase_probability DESC
          ) AS category_rank
    FROM ${common.database}.ml_purchase_probability_scores
)
, expanded AS (
    SELECT
        s.key_value
        , t.product_id
        , s.purchase_probability
        , ROW_NUMBER() OVER (
            PARTITION BY s.key_value
            ORDER BY s.purchase_probability DESC, t.rank_in_category ASC
          ) AS rank_in_logic
    FROM scored s
    JOIN top_category_products t
        ON s.category_id = t.category_id
    WHERE s.category_rank <= 3
)
SELECT
    '${logics.ml_purchase_probability.key_column}' AS key_type
    , key_value
    , 'ml_purchase_probability' AS logic_name
    , product_id
    , purchase_probability AS score
    , rank_in_logic
    , 'ml_purchase_probability' AS reco_reason
FROM expanded
WHERE rank_in_logic <= ${logics.ml_purchase_probability.top_n}
