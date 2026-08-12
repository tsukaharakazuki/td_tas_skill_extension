-- ============================================================
-- test_send_cart_abandon_low_stock_second.sql
-- セカンドテスト配信用SQL（カート放棄 在庫僅少版）
--
-- ⚠️ テスト専用: 実顧客には一切配信しない
--    宛先は dig変数 ${test_recipients} から取得
--
-- テストパターン:
--   1. reco0_nopts : レコメンドなし, ポイントなし
--   2. reco1_nopts : レコメンド1件, ポイントなし
--   3. reco2_pts   : レコメンド2件, ポイントあり
--   4. reco4_pts   : レコメンド4件, ポイントあり（フル表示）
-- ============================================================

WITH

recipients AS (
  SELECT email_address
  FROM UNNEST(SPLIT('${test_recipients}', ',')) AS t(email_address)
),

classified AS (
  SELECT
    s.*,
    CASE
      WHEN s.cart_abandon_recommend_seq1_image_url <> '' AND s.cart_abandon_recommend_seq2_image_url <> ''
       AND s.cart_abandon_recommend_seq3_image_url <> '' AND s.cart_abandon_recommend_seq4_image_url <> '' THEN 'reco4'
      WHEN s.cart_abandon_recommend_seq1_image_url <> '' AND s.cart_abandon_recommend_seq2_image_url <> '' THEN 'reco2'
      WHEN s.cart_abandon_recommend_seq1_image_url <> '' THEN 'reco1'
      ELSE 'reco0'
    END AS reco_pattern,
    CASE
      WHEN c.pointsapproved IS NOT NULL AND CAST(c.pointsapproved AS VARCHAR) <> '0' THEN 'pts'
      ELSE 'nopts'
    END AS pts_pattern,
    c.pointsapproved,
    c.member_name,
    ROW_NUMBER() OVER (
      PARTITION BY
        CASE
          WHEN s.cart_abandon_recommend_seq1_image_url <> '' AND s.cart_abandon_recommend_seq2_image_url <> ''
           AND s.cart_abandon_recommend_seq3_image_url <> '' AND s.cart_abandon_recommend_seq4_image_url <> '' THEN 'reco4'
          WHEN s.cart_abandon_recommend_seq1_image_url <> '' AND s.cart_abandon_recommend_seq2_image_url <> '' THEN 'reco2'
          WHEN s.cart_abandon_recommend_seq1_image_url <> '' THEN 'reco1'
          ELSE 'reco0'
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
  WHERE s.rfm_segment = 'f2plus'
),

sampled AS (
  SELECT * FROM classified
  WHERE rn = 1
    AND (
      (reco_pattern = 'reco0' AND pts_pattern = 'nopts')
      OR (reco_pattern = 'reco1' AND pts_pattern = 'nopts')
      OR (reco_pattern = 'reco2' AND pts_pattern = 'pts')
      OR (reco_pattern = 'reco4' AND pts_pattern = 'pts')
    )
)

SELECT
  SUBSTR(r.email_address, 1, POSITION('@' IN r.email_address) - 1)
    || '+ca_lowstock_' || s.reco_pattern || '_' || s.pts_pattern
    || SUBSTR(r.email_address, POSITION('@' IN r.email_address))
  AS email,
  COALESCE(s.member_name, 'テストユーザー') AS member_name,
  COALESCE(CAST(s.pointsapproved AS VARCHAR), '0') AS pointsapproved,

  s.cart_abandon_recommend_seq1_image_url  AS recommend_seq1_image_url,
  s.cart_abandon_recommend_seq1_item_name  AS recommend_seq1_item_name,
  s.cart_abandon_recommend_seq1_item_url   AS recommend_seq1_item_url,
  s.cart_abandon_recommend_seq1_item_brand AS recommend_seq1_item_brand,
  s.cart_abandon_recommend_seq2_image_url  AS recommend_seq2_image_url,
  s.cart_abandon_recommend_seq2_item_name  AS recommend_seq2_item_name,
  s.cart_abandon_recommend_seq2_item_url   AS recommend_seq2_item_url,
  s.cart_abandon_recommend_seq2_item_brand AS recommend_seq2_item_brand,
  s.cart_abandon_recommend_seq3_image_url  AS recommend_seq3_image_url,
  s.cart_abandon_recommend_seq3_item_name  AS recommend_seq3_item_name,
  s.cart_abandon_recommend_seq3_item_url   AS recommend_seq3_item_url,
  s.cart_abandon_recommend_seq3_item_brand AS recommend_seq3_item_brand,
  s.cart_abandon_recommend_seq4_image_url  AS recommend_seq4_image_url,
  s.cart_abandon_recommend_seq4_item_name  AS recommend_seq4_item_name,
  s.cart_abandon_recommend_seq4_item_url   AS recommend_seq4_item_url,
  s.cart_abandon_recommend_seq4_item_brand AS recommend_seq4_item_brand

FROM sampled s
CROSS JOIN recipients r
