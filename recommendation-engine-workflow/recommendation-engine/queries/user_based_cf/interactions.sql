-- ユーザー間協調フィルタリング用の相互作用データ
-- Python側で member_id × product_id の疎行列に変換し、行列分解を行う。

SELECT
    member_id
    , product_id
    , SUM(quantity) AS interaction_value
    , COUNT(DISTINCT order_id) AS purchase_count
FROM ${common.order_db}.${common.order_tbl}
WHERE TD_INTERVAL(time, '-${logics.user_based_cf.lookback_days}d', 'JST')
    AND member_id IS NOT NULL
    AND product_id IS NOT NULL
GROUP BY member_id, product_id
HAVING SUM(quantity) > 0
