-- ============================================================
-- test_send_cart_abandon_normal_first.sql
-- 初回テスト配信用SQL（カート放棄 ノーマル版: 2通のみ）
--
-- ⚠️ テスト専用: 実顧客には一切配信しない
--    email を test-recipient+<alias>@example.com に完全置換
--
-- 初回テスト: 最も差が出る2パターンで表示確認
--   1. f1_all4_ps_all4_pts : 全スロット埋まり＋ポイントあり（最大表示）
--   2. new_none_ps_none_nopts : 全スロット空（最小表示）
-- ============================================================

WITH

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

sampled AS (
  SELECT * FROM classified
  WHERE rn = 1
    AND (
      -- パターン①: 全部あり（最大表示）
      (rfm_segment = 'f1' AND reco_pattern = 'all4' AND ps_pattern = 'ps_all4' AND pts_pattern = 'pts')
      OR
      -- パターン②: 全部なし（最小表示）
      (rfm_segment = 'new' AND reco_pattern = 'none' AND ps_pattern = 'ps_none' AND pts_pattern = 'nopts')
    )
)

SELECT
  CAST(
    'test-recipient+normal_' || rfm_segment || '_' || reco_pattern || '_' || ps_pattern || '_' || pts_pattern || '@example.com'
    AS VARCHAR
  ) AS email,
  COALESCE(CAST(pointsapproved AS VARCHAR), '0') AS pointsapproved,

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
