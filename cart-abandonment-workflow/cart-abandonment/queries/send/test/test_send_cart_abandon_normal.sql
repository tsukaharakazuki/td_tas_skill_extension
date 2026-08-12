-- ============================================================
-- test_send_cart_abandon_normal.sql
-- テスト配信用SQL（カート放棄 ノーマル版: new / f1）
--
-- ⚠️ テスト専用: 実顧客には一切配信しない
--    email を test-recipient+<alias>@example.com に完全置換
--
-- 目的:
--   レコメンドデータの充填パターン（all4/only2/only1/none）×
--   PS属性パターン（seq5-8あり/なし、ポイントあり/なし）ごとに
--   メールの見え方を確認する
--
-- パターン一覧（最大10通）:
--   1. new_all4_ps_none      : seq1-4全あり, PS推薦なし, ポイントなし
--   2. new_only2_ps_none     : seq1-2のみ, PS推薦なし
--   3. new_only1_ps_none     : seq1のみ, PS推薦なし
--   4. new_none_ps_none      : 推薦なし, PS推薦なし
--   5. f1_all4_ps_all4_pts   : seq1-4全あり, PS推薦全あり, ポイントあり
--   6. f1_all4_ps_none_pts   : seq1-4全あり, PS推薦なし, ポイントあり
--   7. f1_all4_ps_all4_nopts : seq1-4全あり, PS推薦全あり, ポイントなし
--   8. f1_none_ps_none       : 推薦なし, PS推薦なし
--   9. new_all4_ps_all4      : seq1-4全あり, PS推薦全あり（newでもPSあるケース）
--  10. f1_only1_ps_none      : seq1のみ, PS推薦なし
--
-- データソース: storeテーブル（永続履歴）から実データを取得
-- ============================================================

WITH

-- storeテーブルから推薦充填パターンを分類
classified AS (
  SELECT
    s.*,
    CASE
      WHEN s.cart_abandon_recommend_seq1_image_url <> '' AND s.cart_abandon_recommend_seq2_image_url <> ''
       AND s.cart_abandon_recommend_seq3_image_url <> '' AND s.cart_abandon_recommend_seq4_image_url <> '' THEN 'all4'
      WHEN s.cart_abandon_recommend_seq1_image_url <> '' AND s.cart_abandon_recommend_seq2_image_url <> '' THEN 'only2'
      WHEN s.cart_abandon_recommend_seq1_image_url <> '' THEN 'only1'
      ELSE 'none'
    END AS reco_pattern,
    CASE
      WHEN c.recommend_seq5_image_url IS NOT NULL AND c.recommend_seq5_image_url <> ''
       AND c.recommend_seq6_image_url IS NOT NULL AND c.recommend_seq6_image_url <> ''
       AND c.recommend_seq7_image_url IS NOT NULL AND c.recommend_seq7_image_url <> ''
       AND c.recommend_seq8_image_url IS NOT NULL AND c.recommend_seq8_image_url <> '' THEN 'ps_all4'
      WHEN c.recommend_seq5_image_url IS NOT NULL AND c.recommend_seq5_image_url <> '' THEN 'ps_partial'
      ELSE 'ps_none'
    END AS ps_pattern,
    CASE
      WHEN c.pointsapproved IS NOT NULL AND CAST(c.pointsapproved AS VARCHAR) <> '0' THEN 'pts'
      ELSE 'nopts'
    END AS pts_pattern,
    c.pointsapproved,
    c.recommend_seq5_image_url, c.recommend_seq5_item_name, c.recommend_seq5_item_url, c.recommend_seq5_item_brand,
    c.recommend_seq6_image_url, c.recommend_seq6_item_name, c.recommend_seq6_item_url, c.recommend_seq6_item_brand,
    c.recommend_seq7_image_url, c.recommend_seq7_item_name, c.recommend_seq7_item_url, c.recommend_seq7_item_brand,
    c.recommend_seq8_image_url, c.recommend_seq8_item_name, c.recommend_seq8_item_url, c.recommend_seq8_item_brand,
    ROW_NUMBER() OVER (
      PARTITION BY s.rfm_segment,
        CASE
          WHEN s.cart_abandon_recommend_seq1_image_url <> '' AND s.cart_abandon_recommend_seq2_image_url <> ''
           AND s.cart_abandon_recommend_seq3_image_url <> '' AND s.cart_abandon_recommend_seq4_image_url <> '' THEN 'all4'
          WHEN s.cart_abandon_recommend_seq1_image_url <> '' AND s.cart_abandon_recommend_seq2_image_url <> '' THEN 'only2'
          WHEN s.cart_abandon_recommend_seq1_image_url <> '' THEN 'only1'
          ELSE 'none'
        END,
        CASE
          WHEN c.recommend_seq5_image_url IS NOT NULL AND c.recommend_seq5_image_url <> ''
           AND c.recommend_seq6_image_url IS NOT NULL AND c.recommend_seq6_image_url <> ''
           AND c.recommend_seq7_image_url IS NOT NULL AND c.recommend_seq7_image_url <> ''
           AND c.recommend_seq8_image_url IS NOT NULL AND c.recommend_seq8_image_url <> '' THEN 'ps_all4'
          WHEN c.recommend_seq5_image_url IS NOT NULL AND c.recommend_seq5_image_url <> '' THEN 'ps_partial'
          ELSE 'ps_none'
        END,
        CASE
          WHEN c.pointsapproved IS NOT NULL AND CAST(c.pointsapproved AS VARCHAR) <> '0' THEN 'pts'
          ELSE 'nopts'
        END
      ORDER BY s.scheduled_time DESC
    ) AS rn
  FROM cart_abandonment_db.cart_abandonment_store_cart_drop_sent_list_v2 s
  LEFT JOIN (
  SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY time DESC NULLS LAST) AS ps_rn
    FROM customer_attributes_db.customer_attributes
  ) WHERE ps_rn = 1
) c ON s.email = c.email
  WHERE s.rfm_segment IN ('new', 'f1')
),

-- 各パターンから1件ずつ抽出
sampled AS (
  SELECT * FROM classified WHERE rn = 1
)

-- テスト配信用出力（email を固定テストアドレスに完全置換）
SELECT
  -- ⚠️ 実メールアドレスは一切使わない。パターン名をaliasに含めて受信時に判別可能にする
  CAST(
    'test-recipient+normal_' || rfm_segment || '_' || reco_pattern || '_' || ps_pattern || '_' || pts_pattern || '@example.com'
    AS VARCHAR
  ) AS email,
  COALESCE(CAST(pointsapproved AS VARCHAR), '0') AS pointsapproved,

  -- カート放棄ベースの推薦商品（seq1〜4）
  cart_abandon_recommend_seq1_image_url  AS recommend_seq1_image_url,
  cart_abandon_recommend_seq1_item_name  AS recommend_seq1_item_name,
  cart_abandon_recommend_seq1_item_url   AS recommend_seq1_item_url,
  cart_abandon_recommend_seq1_item_brand AS recommend_seq1_item_brand,
  cart_abandon_recommend_seq2_image_url  AS recommend_seq2_image_url,
  cart_abandon_recommend_seq2_item_name  AS recommend_seq2_item_name,
  cart_abandon_recommend_seq2_item_url   AS recommend_seq2_item_url,
  cart_abandon_recommend_seq2_item_brand AS recommend_seq2_item_brand,
  cart_abandon_recommend_seq3_image_url  AS recommend_seq3_image_url,
  cart_abandon_recommend_seq3_item_name  AS recommend_seq3_item_name,
  cart_abandon_recommend_seq3_item_url   AS recommend_seq3_item_url,
  cart_abandon_recommend_seq3_item_brand AS recommend_seq3_item_brand,
  cart_abandon_recommend_seq4_image_url  AS recommend_seq4_image_url,
  cart_abandon_recommend_seq4_item_name  AS recommend_seq4_item_name,
  cart_abandon_recommend_seq4_item_url   AS recommend_seq4_item_url,
  cart_abandon_recommend_seq4_item_brand AS recommend_seq4_item_brand,

  -- パーソナライズドレコメンド（seq5〜8）— PS属性
  COALESCE(recommend_seq5_image_url, '')  AS recommend_seq5_image_url,
  COALESCE(recommend_seq5_item_name, '')  AS recommend_seq5_item_name,
  COALESCE(recommend_seq5_item_url, 'https://example.com/')   AS recommend_seq5_item_url,
  COALESCE(recommend_seq5_item_brand, '') AS recommend_seq5_item_brand,
  COALESCE(recommend_seq6_image_url, '')  AS recommend_seq6_image_url,
  COALESCE(recommend_seq6_item_name, '')  AS recommend_seq6_item_name,
  COALESCE(recommend_seq6_item_url, 'https://example.com/')   AS recommend_seq6_item_url,
  COALESCE(recommend_seq6_item_brand, '') AS recommend_seq6_item_brand,
  COALESCE(recommend_seq7_image_url, '')  AS recommend_seq7_image_url,
  COALESCE(recommend_seq7_item_name, '')  AS recommend_seq7_item_name,
  COALESCE(recommend_seq7_item_url, 'https://example.com/')   AS recommend_seq7_item_url,
  COALESCE(recommend_seq7_item_brand, '') AS recommend_seq7_item_brand,
  COALESCE(recommend_seq8_image_url, '')  AS recommend_seq8_image_url,
  COALESCE(recommend_seq8_item_name, '')  AS recommend_seq8_item_name,
  COALESCE(recommend_seq8_item_url, 'https://example.com/')   AS recommend_seq8_item_url,
  COALESCE(recommend_seq8_item_brand, '') AS recommend_seq8_item_brand

FROM sampled
