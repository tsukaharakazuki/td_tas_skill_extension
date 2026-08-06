-- Pythonで行列分解した候補を共有候補テーブルへ追記する。
SELECT
    key_type
    , key_value
    , logic_name
    , product_id
    , score
    , rank_in_logic
    , reco_reason
FROM reco_user_based_cf
