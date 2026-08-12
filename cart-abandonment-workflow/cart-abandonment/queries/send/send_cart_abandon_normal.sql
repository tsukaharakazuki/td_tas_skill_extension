-- ============================================================
-- send_cart_abandon_normal.sql
-- Engage配信用SQL（カート放棄 v2）
--
-- 対象: 全セグメント（unknown / f0 / f1 / f3plus）
-- テンプレート: [customer] カート放棄 v2
--
-- メール送信先:
--   source_customer.customers の生メールアドレスを使用。
--   push_send_list のハッシュ email と SHA256 で突合して取得する。
--
-- 2026-07-18 改修:
--   - クーポン情報を params 化（coupon.expiry_date / coupon.expiry_label）し、
--     期限超過時はクーポン欄を空にするガードを追加
--     （Liquid側は coupon_code 空で非表示になるテンプレート実装が前提）
--   - customers の email 重複（少数存在）によるファンアウト防止のため
--     配信先取得をemail単位のdedupサブクエリに変更
-- ============================================================

WITH coupon_state AS (
  SELECT
    CAST('${coupon.expiry_date}' AS DATE)
      >= CAST(TD_TIME_FORMAT(TD_SCHEDULED_TIME(), 'yyyy-MM-dd', 'JST') AS DATE) AS active
)

SELECT
  m.email,  -- 生メールアドレス（配信先）
  COALESCE(CAST(c.pointsapproved AS VARCHAR), '0') AS pointsapproved,

  -- 在庫僅少フラグ（カート商品のうち1つでも在庫僅少があれば '1'）
  CASE
    WHEN COALESCE(sk1.low_stock, '') = '1'
      OR COALESCE(sk2.low_stock, '') = '1'
      OR COALESCE(sk3.low_stock, '') = '1'
      OR COALESCE(sk4.low_stock, '') = '1'
    THEN '1' ELSE ''
  END AS has_low_stock,

  -- クーポン情報（セグメント別・期限内のみ表示）
  CASE WHEN cs.active THEN
    CASE p.cart_abandon_rfm_segment
      WHEN 'unknown' THEN '<COUPON_CODE_UNKNOWN>'
      WHEN 'f0'      THEN '<COUPON_CODE_F0>'
      WHEN 'f1'      THEN '<COUPON_CODE_F1>'
      WHEN 'f3plus'  THEN '<COUPON_CODE_F3PLUS>'
      ELSE ''
    END
  ELSE '' END AS coupon_code,
  CASE WHEN cs.active THEN
    CASE p.cart_abandon_rfm_segment
      WHEN 'f0' THEN '<COUPON_IMAGE_URL_F0>'
      ELSE           '<COUPON_IMAGE_URL_DEFAULT>'
    END
  ELSE '' END AS coupon_image_url,
  CASE WHEN cs.active THEN
    CASE p.cart_abandon_rfm_segment
      WHEN 'unknown' THEN 'オンライン限定 5,500円(税込)以上で使える500円クーポン'
      WHEN 'f0'      THEN 'オンライン限定 11,000円(税込)以上で使える1,000円クーポン'
      WHEN 'f1'      THEN 'オンライン限定 5,500円(税込)以上で使える500円クーポン'
      WHEN 'f3plus'  THEN 'オンライン限定 5,500円(税込)以上で使える500円クーポン'
      ELSE ''
    END
  ELSE '' END AS coupon_description,
  CASE WHEN cs.active THEN '${coupon.expiry_label}' ELSE '' END AS coupon_expiry,

  -- カート商品（seq1〜4）- 公開商品のみ表示
  CASE WHEN COALESCE(sk1.is_available, '') = '1' THEN COALESCE(p.cart_item_seq1_image_url, '') ELSE '' END AS cart_item_seq1_image_url,
  CASE WHEN COALESCE(sk1.is_available, '') = '1' THEN COALESCE(p.cart_item_seq1_item_name, '') ELSE '' END AS cart_item_seq1_item_name,
  CASE WHEN COALESCE(sk1.is_available, '') = '1' THEN COALESCE(p.cart_item_seq1_item_url, '')  ELSE '' END AS cart_item_seq1_item_url,
  CASE WHEN COALESCE(sk1.is_available, '') = '1' THEN COALESCE(p.cart_item_seq1_item_brand, '') ELSE '' END AS cart_item_seq1_item_brand,
  CASE WHEN COALESCE(sk1.is_available, '') = '1' THEN COALESCE(sk1.low_stock, '') ELSE '' END AS cart_item_seq1_low_stock,
  CASE WHEN COALESCE(sk1.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(sk1.taxin_price AS BIGINT)), '') ELSE '' END AS cart_item_seq1_price,
  CASE WHEN COALESCE(sk1.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(sk1.taxin_compare_at_price AS BIGINT)), '') ELSE '' END AS cart_item_seq1_price_org,
  CASE WHEN COALESCE(sk1.is_available, '') = '1' AND sk1.sale_flag = '1' THEN '1' ELSE '' END AS cart_item_seq1_sale_flag,
  CASE WHEN COALESCE(sk1.is_available, '') = '1' AND sk1.sale_flag = '1' THEN COALESCE(sk1.discount_rate, '') ELSE '' END AS cart_item_seq1_discount_rate,

  CASE WHEN COALESCE(sk2.is_available, '') = '1' THEN COALESCE(p.cart_item_seq2_image_url, '') ELSE '' END AS cart_item_seq2_image_url,
  CASE WHEN COALESCE(sk2.is_available, '') = '1' THEN COALESCE(p.cart_item_seq2_item_name, '') ELSE '' END AS cart_item_seq2_item_name,
  CASE WHEN COALESCE(sk2.is_available, '') = '1' THEN COALESCE(p.cart_item_seq2_item_url, '')  ELSE '' END AS cart_item_seq2_item_url,
  CASE WHEN COALESCE(sk2.is_available, '') = '1' THEN COALESCE(p.cart_item_seq2_item_brand, '') ELSE '' END AS cart_item_seq2_item_brand,
  CASE WHEN COALESCE(sk2.is_available, '') = '1' THEN COALESCE(sk2.low_stock, '') ELSE '' END AS cart_item_seq2_low_stock,
  CASE WHEN COALESCE(sk2.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(sk2.taxin_price AS BIGINT)), '') ELSE '' END AS cart_item_seq2_price,
  CASE WHEN COALESCE(sk2.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(sk2.taxin_compare_at_price AS BIGINT)), '') ELSE '' END AS cart_item_seq2_price_org,
  CASE WHEN COALESCE(sk2.is_available, '') = '1' AND sk2.sale_flag = '1' THEN '1' ELSE '' END AS cart_item_seq2_sale_flag,
  CASE WHEN COALESCE(sk2.is_available, '') = '1' AND sk2.sale_flag = '1' THEN COALESCE(sk2.discount_rate, '') ELSE '' END AS cart_item_seq2_discount_rate,

  CASE WHEN COALESCE(sk3.is_available, '') = '1' THEN COALESCE(p.cart_item_seq3_image_url, '') ELSE '' END AS cart_item_seq3_image_url,
  CASE WHEN COALESCE(sk3.is_available, '') = '1' THEN COALESCE(p.cart_item_seq3_item_name, '') ELSE '' END AS cart_item_seq3_item_name,
  CASE WHEN COALESCE(sk3.is_available, '') = '1' THEN COALESCE(p.cart_item_seq3_item_url, '')  ELSE '' END AS cart_item_seq3_item_url,
  CASE WHEN COALESCE(sk3.is_available, '') = '1' THEN COALESCE(p.cart_item_seq3_item_brand, '') ELSE '' END AS cart_item_seq3_item_brand,
  CASE WHEN COALESCE(sk3.is_available, '') = '1' THEN COALESCE(sk3.low_stock, '') ELSE '' END AS cart_item_seq3_low_stock,
  CASE WHEN COALESCE(sk3.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(sk3.taxin_price AS BIGINT)), '') ELSE '' END AS cart_item_seq3_price,
  CASE WHEN COALESCE(sk3.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(sk3.taxin_compare_at_price AS BIGINT)), '') ELSE '' END AS cart_item_seq3_price_org,
  CASE WHEN COALESCE(sk3.is_available, '') = '1' AND sk3.sale_flag = '1' THEN '1' ELSE '' END AS cart_item_seq3_sale_flag,
  CASE WHEN COALESCE(sk3.is_available, '') = '1' AND sk3.sale_flag = '1' THEN COALESCE(sk3.discount_rate, '') ELSE '' END AS cart_item_seq3_discount_rate,

  CASE WHEN COALESCE(sk4.is_available, '') = '1' THEN COALESCE(p.cart_item_seq4_image_url, '') ELSE '' END AS cart_item_seq4_image_url,
  CASE WHEN COALESCE(sk4.is_available, '') = '1' THEN COALESCE(p.cart_item_seq4_item_name, '') ELSE '' END AS cart_item_seq4_item_name,
  CASE WHEN COALESCE(sk4.is_available, '') = '1' THEN COALESCE(p.cart_item_seq4_item_url, '')  ELSE '' END AS cart_item_seq4_item_url,
  CASE WHEN COALESCE(sk4.is_available, '') = '1' THEN COALESCE(p.cart_item_seq4_item_brand, '') ELSE '' END AS cart_item_seq4_item_brand,
  CASE WHEN COALESCE(sk4.is_available, '') = '1' THEN COALESCE(sk4.low_stock, '') ELSE '' END AS cart_item_seq4_low_stock,
  CASE WHEN COALESCE(sk4.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(sk4.taxin_price AS BIGINT)), '') ELSE '' END AS cart_item_seq4_price,
  CASE WHEN COALESCE(sk4.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(sk4.taxin_compare_at_price AS BIGINT)), '') ELSE '' END AS cart_item_seq4_price_org,
  CASE WHEN COALESCE(sk4.is_available, '') = '1' AND sk4.sale_flag = '1' THEN '1' ELSE '' END AS cart_item_seq4_sale_flag,
  CASE WHEN COALESCE(sk4.is_available, '') = '1' AND sk4.sale_flag = '1' THEN COALESCE(sk4.discount_rate, '') ELSE '' END AS cart_item_seq4_discount_rate,

  -- レコメンド商品（seq1〜4）- 公開商品のみ表示 + 価格情報
  CASE WHEN COALESCE(rsk1.is_available, '') = '1' THEN p.cart_abandon_recommend_seq1_image_url  ELSE '' END AS recommend_seq1_image_url,
  CASE WHEN COALESCE(rsk1.is_available, '') = '1' THEN p.cart_abandon_recommend_seq1_item_name  ELSE '' END AS recommend_seq1_item_name,
  CASE WHEN COALESCE(rsk1.is_available, '') = '1' THEN p.cart_abandon_recommend_seq1_item_url   ELSE '' END AS recommend_seq1_item_url,
  CASE WHEN COALESCE(rsk1.is_available, '') = '1' THEN p.cart_abandon_recommend_seq1_item_brand ELSE '' END AS recommend_seq1_item_brand,
  CASE WHEN COALESCE(rsk1.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(rsk1.taxin_price AS BIGINT)), '') ELSE '' END AS recommend_seq1_price,
  CASE WHEN COALESCE(rsk1.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(rsk1.taxin_compare_at_price AS BIGINT)), '') ELSE '' END AS recommend_seq1_price_org,
  CASE WHEN COALESCE(rsk1.is_available, '') = '1' AND rsk1.sale_flag = '1' THEN '1' ELSE '' END AS recommend_seq1_sale_flag,
  CASE WHEN COALESCE(rsk1.is_available, '') = '1' AND rsk1.sale_flag = '1' THEN COALESCE(rsk1.discount_rate, '') ELSE '' END AS recommend_seq1_discount_rate,

  CASE WHEN COALESCE(rsk2.is_available, '') = '1' THEN p.cart_abandon_recommend_seq2_image_url  ELSE '' END AS recommend_seq2_image_url,
  CASE WHEN COALESCE(rsk2.is_available, '') = '1' THEN p.cart_abandon_recommend_seq2_item_name  ELSE '' END AS recommend_seq2_item_name,
  CASE WHEN COALESCE(rsk2.is_available, '') = '1' THEN p.cart_abandon_recommend_seq2_item_url   ELSE '' END AS recommend_seq2_item_url,
  CASE WHEN COALESCE(rsk2.is_available, '') = '1' THEN p.cart_abandon_recommend_seq2_item_brand ELSE '' END AS recommend_seq2_item_brand,
  CASE WHEN COALESCE(rsk2.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(rsk2.taxin_price AS BIGINT)), '') ELSE '' END AS recommend_seq2_price,
  CASE WHEN COALESCE(rsk2.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(rsk2.taxin_compare_at_price AS BIGINT)), '') ELSE '' END AS recommend_seq2_price_org,
  CASE WHEN COALESCE(rsk2.is_available, '') = '1' AND rsk2.sale_flag = '1' THEN '1' ELSE '' END AS recommend_seq2_sale_flag,
  CASE WHEN COALESCE(rsk2.is_available, '') = '1' AND rsk2.sale_flag = '1' THEN COALESCE(rsk2.discount_rate, '') ELSE '' END AS recommend_seq2_discount_rate,

  CASE WHEN COALESCE(rsk3.is_available, '') = '1' THEN p.cart_abandon_recommend_seq3_image_url  ELSE '' END AS recommend_seq3_image_url,
  CASE WHEN COALESCE(rsk3.is_available, '') = '1' THEN p.cart_abandon_recommend_seq3_item_name  ELSE '' END AS recommend_seq3_item_name,
  CASE WHEN COALESCE(rsk3.is_available, '') = '1' THEN p.cart_abandon_recommend_seq3_item_url   ELSE '' END AS recommend_seq3_item_url,
  CASE WHEN COALESCE(rsk3.is_available, '') = '1' THEN p.cart_abandon_recommend_seq3_item_brand ELSE '' END AS recommend_seq3_item_brand,
  CASE WHEN COALESCE(rsk3.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(rsk3.taxin_price AS BIGINT)), '') ELSE '' END AS recommend_seq3_price,
  CASE WHEN COALESCE(rsk3.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(rsk3.taxin_compare_at_price AS BIGINT)), '') ELSE '' END AS recommend_seq3_price_org,
  CASE WHEN COALESCE(rsk3.is_available, '') = '1' AND rsk3.sale_flag = '1' THEN '1' ELSE '' END AS recommend_seq3_sale_flag,
  CASE WHEN COALESCE(rsk3.is_available, '') = '1' AND rsk3.sale_flag = '1' THEN COALESCE(rsk3.discount_rate, '') ELSE '' END AS recommend_seq3_discount_rate,

  CASE WHEN COALESCE(rsk4.is_available, '') = '1' THEN p.cart_abandon_recommend_seq4_image_url  ELSE '' END AS recommend_seq4_image_url,
  CASE WHEN COALESCE(rsk4.is_available, '') = '1' THEN p.cart_abandon_recommend_seq4_item_name  ELSE '' END AS recommend_seq4_item_name,
  CASE WHEN COALESCE(rsk4.is_available, '') = '1' THEN p.cart_abandon_recommend_seq4_item_url   ELSE '' END AS recommend_seq4_item_url,
  CASE WHEN COALESCE(rsk4.is_available, '') = '1' THEN p.cart_abandon_recommend_seq4_item_brand ELSE '' END AS recommend_seq4_item_brand,
  CASE WHEN COALESCE(rsk4.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(rsk4.taxin_price AS BIGINT)), '') ELSE '' END AS recommend_seq4_price,
  CASE WHEN COALESCE(rsk4.is_available, '') = '1' THEN COALESCE(FORMAT('%,d', TRY_CAST(rsk4.taxin_compare_at_price AS BIGINT)), '') ELSE '' END AS recommend_seq4_price_org,
  CASE WHEN COALESCE(rsk4.is_available, '') = '1' AND rsk4.sale_flag = '1' THEN '1' ELSE '' END AS recommend_seq4_sale_flag,
  CASE WHEN COALESCE(rsk4.is_available, '') = '1' AND rsk4.sale_flag = '1' THEN COALESCE(rsk4.discount_rate, '') ELSE '' END AS recommend_seq4_discount_rate

FROM cart_abandonment_db.cart_abandonment_push_send_list p
CROSS JOIN coupon_state cs
-- 生メールアドレスを取得（ハッシュ突合・email単位dedup・配信許諾済みのみ）
JOIN (
  SELECT email
  FROM source_customer.customers
  WHERE email_marketing_consent = 'SUBSCRIBED'
  GROUP BY email
) m
  ON p.email = LOWER(TO_HEX(SHA256(CAST(m.email AS VARBINARY))))
-- PS属性（ポイント）
LEFT JOIN (
  SELECT email, MAX(pointsapproved) AS pointsapproved
  FROM customer_attributes_db.customer_attributes
  GROUP BY email
) c
  ON p.email = c.email
-- カート商品の在庫・公開状態チェック
LEFT JOIN cart_abandonment_db.reco_product_stock sk1
  ON REGEXP_EXTRACT(p.cart_item_seq1_item_url, '/products/([^/?]+)', 1) = sk1.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock sk2
  ON REGEXP_EXTRACT(p.cart_item_seq2_item_url, '/products/([^/?]+)', 1) = sk2.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock sk3
  ON REGEXP_EXTRACT(p.cart_item_seq3_item_url, '/products/([^/?]+)', 1) = sk3.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock sk4
  ON REGEXP_EXTRACT(p.cart_item_seq4_item_url, '/products/([^/?]+)', 1) = sk4.item_id
-- レコメンド商品の公開状態チェック
LEFT JOIN cart_abandonment_db.reco_product_stock rsk1
  ON REGEXP_EXTRACT(p.cart_abandon_recommend_seq1_item_url, '/products/([^/?]+)', 1) = rsk1.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock rsk2
  ON REGEXP_EXTRACT(p.cart_abandon_recommend_seq2_item_url, '/products/([^/?]+)', 1) = rsk2.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock rsk3
  ON REGEXP_EXTRACT(p.cart_abandon_recommend_seq3_item_url, '/products/([^/?]+)', 1) = rsk3.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock rsk4
  ON REGEXP_EXTRACT(p.cart_abandon_recommend_seq4_item_url, '/products/([^/?]+)', 1) = rsk4.item_id
WHERE p.email IS NOT NULL
