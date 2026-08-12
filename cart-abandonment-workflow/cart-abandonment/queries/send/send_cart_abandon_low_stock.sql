-- ============================================================
-- send_cart_abandon_low_stock.sql
-- Engage配信用SQL（カート放棄 在庫僅少版）
--
-- ⚠️ 現在は未使用（send_email.dig は normal 版で全セグメント統一配信）。
--    将来有効化する場合もこのままで安全なように、2026-07-18 に
--    配信許諾フィルタ（email_marketing_consent = 'SUBSCRIBED'）と
--    email単位dedupを追加済み。
--
-- 対象: rfm_segment = 'f3plus'
-- テンプレート: [customer] カート放棄_在庫僅少 v1
-- ============================================================

SELECT
  m.email,  -- 生メールアドレス（配信先）
  COALESCE(c.member_name, '') AS member_name,
  COALESCE(CAST(c.pointsapproved AS VARCHAR), '0') AS pointsapproved,

  -- カート放棄ベースの推薦商品（seq1〜4）
  p.cart_abandon_recommend_seq1_image_url  AS recommend_seq1_image_url,
  p.cart_abandon_recommend_seq1_item_name  AS recommend_seq1_item_name,
  p.cart_abandon_recommend_seq1_item_url   AS recommend_seq1_item_url,
  p.cart_abandon_recommend_seq1_item_brand AS recommend_seq1_item_brand,
  p.cart_abandon_recommend_seq2_image_url  AS recommend_seq2_image_url,
  p.cart_abandon_recommend_seq2_item_name  AS recommend_seq2_item_name,
  p.cart_abandon_recommend_seq2_item_url   AS recommend_seq2_item_url,
  p.cart_abandon_recommend_seq2_item_brand AS recommend_seq2_item_brand,
  p.cart_abandon_recommend_seq3_image_url  AS recommend_seq3_image_url,
  p.cart_abandon_recommend_seq3_item_name  AS recommend_seq3_item_name,
  p.cart_abandon_recommend_seq3_item_url   AS recommend_seq3_item_url,
  p.cart_abandon_recommend_seq3_item_brand AS recommend_seq3_item_brand,
  p.cart_abandon_recommend_seq4_image_url  AS recommend_seq4_image_url,
  p.cart_abandon_recommend_seq4_item_name  AS recommend_seq4_item_name,
  p.cart_abandon_recommend_seq4_item_url   AS recommend_seq4_item_url,
  p.cart_abandon_recommend_seq4_item_brand AS recommend_seq4_item_brand,

  -- パーソナライズドレコメンド（seq5〜8）— PS既存属性から取得
  COALESCE(c.recommend_seq5_image_url, '')  AS recommend_seq5_image_url,
  COALESCE(c.recommend_seq5_item_name, '')  AS recommend_seq5_item_name,
  COALESCE(c.recommend_seq5_item_url, 'https://example.com/')   AS recommend_seq5_item_url,
  COALESCE(c.recommend_seq5_item_brand, '') AS recommend_seq5_item_brand,
  COALESCE(c.recommend_seq6_image_url, '')  AS recommend_seq6_image_url,
  COALESCE(c.recommend_seq6_item_name, '')  AS recommend_seq6_item_name,
  COALESCE(c.recommend_seq6_item_url, 'https://example.com/')   AS recommend_seq6_item_url,
  COALESCE(c.recommend_seq6_item_brand, '') AS recommend_seq6_item_brand,
  COALESCE(c.recommend_seq7_image_url, '')  AS recommend_seq7_image_url,
  COALESCE(c.recommend_seq7_item_name, '')  AS recommend_seq7_item_name,
  COALESCE(c.recommend_seq7_item_url, 'https://example.com/')   AS recommend_seq7_item_url,
  COALESCE(c.recommend_seq7_item_brand, '') AS recommend_seq7_item_brand,
  COALESCE(c.recommend_seq8_image_url, '')  AS recommend_seq8_image_url,
  COALESCE(c.recommend_seq8_item_name, '')  AS recommend_seq8_item_name,
  COALESCE(c.recommend_seq8_item_url, 'https://example.com/')   AS recommend_seq8_item_url,
  COALESCE(c.recommend_seq8_item_brand, '') AS recommend_seq8_item_brand

FROM cart_abandonment_db.cart_abandonment_push_send_list p
-- 生メールアドレスを取得（ハッシュ突合・email単位dedup・配信許諾済みのみ）
JOIN (
  SELECT email
  FROM source_customer.customers
  WHERE email_marketing_consent = 'SUBSCRIBED'
  GROUP BY email
) m
  ON p.email = LOWER(TO_HEX(SHA256(CAST(m.email AS VARBINARY))))
-- PS属性（ポイント・パーソナライズドレコメンド）
LEFT JOIN (
  SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY time DESC NULLS LAST) AS ps_rn
    FROM customer_attributes_db.customer_attributes
  ) WHERE ps_rn = 1
) c
  ON p.email = c.email
WHERE p.email IS NOT NULL
  AND p.cart_abandon_rfm_segment = 'f3plus'
