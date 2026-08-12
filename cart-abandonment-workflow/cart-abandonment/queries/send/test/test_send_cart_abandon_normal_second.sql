-- ============================================================
-- test_send_cart_abandon_normal_second.sql
-- セカンドテスト配信用SQL（カート放棄 v2テンプレート）
--
-- ⚠️ テスト専用: 実顧客には一切配信しない
--    宛先は dig変数 ${test_recipients} から取得
--
-- テストパターン:
--   1. cart1_reco0_nostock : カート商品1個(在庫僅少), レコメンドなし, クーポンunknown
--   2. cart2_reco0_normal  : カート商品2個(在庫十分), レコメンドなし, クーポンf0
--   3. cart3_reco1_mixed   : カート商品3個(1個在庫僅少), レコメンド1個, セグメント別オファー
--   4. cart4_reco2_normal  : カート商品4個(在庫十分), レコメンド2個, クーポンf3plus
--
-- データソース:
--   storeテーブル（実際のカート放棄データ）
--   reco_product_stock（在庫・公開状態）
-- ============================================================

WITH

recipients AS (
  SELECT email_address
  FROM UNNEST(SPLIT('${test_recipients}', ',')) AS t(email_address)
),

-- storeテーブルからカート商品の実データ取得（公開商品のみ）
cart_items AS (
  SELECT DISTINCT
    s.cart_abandon_item_id AS item_id,
    s.cart_abandon_item_name AS item_name,
    s.cart_abandon_image_url AS image_url,
    s.cart_abandon_item_url AS item_url,
    s.cart_abandon_brand AS brand_name,
    COALESCE(sk.low_stock, '') AS low_stock,
    COALESCE(CAST(pd.selling_price AS VARCHAR), '') AS price,
    COALESCE(CAST(pd.price_org AS VARCHAR), '') AS price_org,
    CASE WHEN pd.sale_flag = 1 THEN '1' ELSE '' END AS sale_flag
  FROM cart_abandonment_db.cart_abandonment_store_cart_drop_sent_list_v2 s
  JOIN cart_abandonment_db.reco_product_stock sk ON s.cart_abandon_item_id = sk.item_id
  LEFT JOIN cart_abandonment_db.reco_product_detail pd ON s.cart_abandon_item_id = pd.item_id
  WHERE s.cart_abandon_image_url IS NOT NULL AND s.cart_abandon_image_url <> ''
    AND s.cart_abandon_item_url IS NOT NULL AND s.cart_abandon_item_url <> ''
    AND sk.is_published = '1'
),

cart_items_numbered AS (
  SELECT *, ROW_NUMBER() OVER (ORDER BY item_id) AS prod_no
  FROM cart_items
),

-- 在庫僅少の商品を別途取得
low_stock_items AS (
  SELECT *, ROW_NUMBER() OVER (ORDER BY item_id) AS ls_no
  FROM cart_items
  WHERE low_stock = '1'
),

-- storeテーブルからレコメンドデータ（公開商品のみ）
real_reco AS (
  SELECT
    s.cart_abandon_recommend_seq1_image_url AS reco1_image,
    s.cart_abandon_recommend_seq1_item_name AS reco1_name,
    s.cart_abandon_recommend_seq1_item_url AS reco1_url,
    s.cart_abandon_recommend_seq1_item_brand AS reco1_brand,
    s.cart_abandon_recommend_seq2_image_url AS reco2_image,
    s.cart_abandon_recommend_seq2_item_name AS reco2_name,
    s.cart_abandon_recommend_seq2_item_url AS reco2_url,
    s.cart_abandon_recommend_seq2_item_brand AS reco2_brand,
    ROW_NUMBER() OVER (ORDER BY s.scheduled_time DESC) AS rn
  FROM cart_abandonment_db.cart_abandonment_store_cart_drop_sent_list_v2 s
  JOIN cart_abandonment_db.reco_product_stock rsk1
    ON REGEXP_EXTRACT(s.cart_abandon_recommend_seq1_item_url, '/products/([^/?]+)', 1) = rsk1.item_id
  WHERE s.cart_abandon_recommend_seq1_image_url <> ''
    AND s.cart_abandon_recommend_seq2_image_url <> ''
    AND rsk1.is_published = '1'
),

-- パターン別にデータを構築
patterns AS (
  -- パターン1: カート商品1個（在庫僅少）, レコメンドなし, クーポン=unknown(<COUPON_CODE_UNKNOWN>)
  SELECT
    'cart1_reco0_lowstock' AS pattern_name,
    '1' AS has_low_stock,
    '<COUPON_CODE_UNKNOWN>' AS coupon_code,
    '<COUPON_IMAGE_URL_DEFAULT>' AS coupon_image_url,
    'オンライン限定 5,500円(税込)以上で使える500円クーポン' AS coupon_description,
    '2026年8月31日(月) 23:59まで' AS coupon_expiry,
    '0' AS pointsapproved,
    -- カート商品1個（在庫僅少）
    MAX(CASE WHEN ls_no = 1 THEN image_url END) AS cart_item_seq1_image_url,
    MAX(CASE WHEN ls_no = 1 THEN item_name END) AS cart_item_seq1_item_name,
    MAX(CASE WHEN ls_no = 1 THEN item_url END)  AS cart_item_seq1_item_url,
    MAX(CASE WHEN ls_no = 1 THEN brand_name END) AS cart_item_seq1_item_brand,
    '1' AS cart_item_seq1_low_stock,
    '' AS cart_item_seq2_image_url, '' AS cart_item_seq2_item_name, '' AS cart_item_seq2_item_url, '' AS cart_item_seq2_item_brand, '' AS cart_item_seq2_low_stock,
    '' AS cart_item_seq3_image_url, '' AS cart_item_seq3_item_name, '' AS cart_item_seq3_item_url, '' AS cart_item_seq3_item_brand, '' AS cart_item_seq3_low_stock,
    '' AS cart_item_seq4_image_url, '' AS cart_item_seq4_item_name, '' AS cart_item_seq4_item_url, '' AS cart_item_seq4_item_brand, '' AS cart_item_seq4_low_stock,
    '' AS recommend_seq1_image_url, '' AS recommend_seq1_item_name, '' AS recommend_seq1_item_url, '' AS recommend_seq1_item_brand,
    '' AS recommend_seq2_image_url, '' AS recommend_seq2_item_name, '' AS recommend_seq2_item_url, '' AS recommend_seq2_item_brand,
    '' AS recommend_seq3_image_url, '' AS recommend_seq3_item_name, '' AS recommend_seq3_item_url, '' AS recommend_seq3_item_brand,
    '' AS recommend_seq4_image_url, '' AS recommend_seq4_item_name, '' AS recommend_seq4_item_url, '' AS recommend_seq4_item_brand
  FROM low_stock_items WHERE ls_no <= 1

  UNION ALL

  -- パターン2: カート商品2個（在庫十分）, レコメンドなし, クーポン=f0(<COUPON_CODE_F0>)
  SELECT
    'cart2_reco0_normal',
    '' AS has_low_stock,
    '<COUPON_CODE_F0>' AS coupon_code,
    '<COUPON_IMAGE_URL_F0>' AS coupon_image_url,
    'オンライン限定 11,000円(税込)以上で使える1,000円クーポン' AS coupon_description,
    '2026年8月31日(月) 23:59まで' AS coupon_expiry,
    '250' AS pointsapproved,
    MAX(CASE WHEN prod_no = 1 THEN image_url END), MAX(CASE WHEN prod_no = 1 THEN item_name END), MAX(CASE WHEN prod_no = 1 THEN item_url END), MAX(CASE WHEN prod_no = 1 THEN brand_name END), '' AS cart_item_seq1_low_stock,
    MAX(CASE WHEN prod_no = 2 THEN image_url END), MAX(CASE WHEN prod_no = 2 THEN item_name END), MAX(CASE WHEN prod_no = 2 THEN item_url END), MAX(CASE WHEN prod_no = 2 THEN brand_name END), '' AS cart_item_seq2_low_stock,
    '', '', '', '', '',
    '', '', '', '', '',
    '', '', '', '',
    '', '', '', '',
    '', '', '', '',
    '', '', '', ''
  FROM cart_items_numbered WHERE prod_no <= 2 AND low_stock <> '1'

  UNION ALL

  -- パターン3: カート商品3個（1個在庫僅少）, レコメンド1個, クーポン=f1(<COUPON_CODE_F1>)
  SELECT
    'cart3_reco1_mixed',
    '1' AS has_low_stock,
    '<COUPON_CODE_F1>' AS coupon_code,
    '<COUPON_IMAGE_URL_DEFAULT>' AS coupon_image_url,
    'オンライン限定 5,500円(税込)以上で使える500円クーポン' AS coupon_description,
    '2026年8月31日(月) 23:59まで' AS coupon_expiry,
    '500' AS pointsapproved,
    ci.c3_image, ci.c3_name, ci.c3_url, ci.c3_brand, '' AS cart_item_seq1_low_stock,
    ci.c4_image, ci.c4_name, ci.c4_url, ci.c4_brand, '' AS cart_item_seq2_low_stock,
    ls.ls_image, ls.ls_name, ls.ls_url, ls.ls_brand, '1' AS cart_item_seq3_low_stock,
    '', '', '', '', '',
    rr.reco1_image, rr.reco1_name, rr.reco1_url, rr.reco1_brand,
    '', '', '', '',
    '', '', '', '',
    '', '', '', ''
  FROM (
    SELECT
      MAX(CASE WHEN prod_no = 3 THEN image_url END) AS c3_image, MAX(CASE WHEN prod_no = 3 THEN item_name END) AS c3_name, MAX(CASE WHEN prod_no = 3 THEN item_url END) AS c3_url, MAX(CASE WHEN prod_no = 3 THEN brand_name END) AS c3_brand,
      MAX(CASE WHEN prod_no = 4 THEN image_url END) AS c4_image, MAX(CASE WHEN prod_no = 4 THEN item_name END) AS c4_name, MAX(CASE WHEN prod_no = 4 THEN item_url END) AS c4_url, MAX(CASE WHEN prod_no = 4 THEN brand_name END) AS c4_brand
    FROM cart_items_numbered WHERE prod_no BETWEEN 3 AND 4 AND low_stock <> '1'
  ) ci
  CROSS JOIN (
    SELECT MAX(CASE WHEN ls_no = 2 THEN image_url END) AS ls_image, MAX(CASE WHEN ls_no = 2 THEN item_name END) AS ls_name, MAX(CASE WHEN ls_no = 2 THEN item_url END) AS ls_url, MAX(CASE WHEN ls_no = 2 THEN brand_name END) AS ls_brand
    FROM low_stock_items WHERE ls_no <= 2
  ) ls
  CROSS JOIN (SELECT * FROM real_reco WHERE rn = 1) rr

  UNION ALL

  -- パターン4: カート商品4個（在庫十分）, レコメンド2個, クーポン=f3plus(<COUPON_CODE_F3PLUS>)
  SELECT
    'cart4_reco2_normal',
    '' AS has_low_stock,
    '<COUPON_CODE_F3PLUS>' AS coupon_code,
    '<COUPON_IMAGE_URL_DEFAULT>' AS coupon_image_url,
    'オンライン限定 5,500円(税込)以上で使える500円クーポン' AS coupon_description,
    '2026年8月31日(月) 23:59まで' AS coupon_expiry,
    '1200' AS pointsapproved,
    ci.c5_image, ci.c5_name, ci.c5_url, ci.c5_brand, '',
    ci.c6_image, ci.c6_name, ci.c6_url, ci.c6_brand, '',
    ci.c7_image, ci.c7_name, ci.c7_url, ci.c7_brand, '',
    ci.c8_image, ci.c8_name, ci.c8_url, ci.c8_brand, '',
    rr.reco1_image, rr.reco1_name, rr.reco1_url, rr.reco1_brand,
    rr.reco2_image, rr.reco2_name, rr.reco2_url, rr.reco2_brand,
    '', '', '', '',
    '', '', '', ''
  FROM (
    SELECT
      MAX(CASE WHEN prod_no = 5 THEN image_url END) AS c5_image, MAX(CASE WHEN prod_no = 5 THEN item_name END) AS c5_name, MAX(CASE WHEN prod_no = 5 THEN item_url END) AS c5_url, MAX(CASE WHEN prod_no = 5 THEN brand_name END) AS c5_brand,
      MAX(CASE WHEN prod_no = 6 THEN image_url END) AS c6_image, MAX(CASE WHEN prod_no = 6 THEN item_name END) AS c6_name, MAX(CASE WHEN prod_no = 6 THEN item_url END) AS c6_url, MAX(CASE WHEN prod_no = 6 THEN brand_name END) AS c6_brand,
      MAX(CASE WHEN prod_no = 7 THEN image_url END) AS c7_image, MAX(CASE WHEN prod_no = 7 THEN item_name END) AS c7_name, MAX(CASE WHEN prod_no = 7 THEN item_url END) AS c7_url, MAX(CASE WHEN prod_no = 7 THEN brand_name END) AS c7_brand,
      MAX(CASE WHEN prod_no = 8 THEN image_url END) AS c8_image, MAX(CASE WHEN prod_no = 8 THEN item_name END) AS c8_name, MAX(CASE WHEN prod_no = 8 THEN item_url END) AS c8_url, MAX(CASE WHEN prod_no = 8 THEN brand_name END) AS c8_brand
    FROM cart_items_numbered WHERE prod_no BETWEEN 5 AND 8 AND low_stock <> '1'
  ) ci
  CROSS JOIN (SELECT * FROM real_reco WHERE rn = 1) rr
)

-- 各パターン × 各宛先 に展開（エイリアスにランダム3桁付与で重複回避）
SELECT
  SUBSTR(r.email_address, 1, POSITION('@' IN r.email_address) - 1)
    || '+ca_v2_' || p.pattern_name || '-' || SUBSTR(TO_HEX(SHA256(CAST(CAST(RANDOM() AS VARCHAR) AS VARBINARY))), 1, 3)
    || SUBSTR(r.email_address, POSITION('@' IN r.email_address))
  AS email,
  p.pointsapproved,
  p.has_low_stock,
  p.coupon_code,
  p.coupon_image_url,
  p.coupon_description,
  p.coupon_expiry,
  p.cart_item_seq1_image_url, p.cart_item_seq1_item_name, p.cart_item_seq1_item_url, p.cart_item_seq1_item_brand, p.cart_item_seq1_low_stock,
  p.cart_item_seq2_image_url, p.cart_item_seq2_item_name, p.cart_item_seq2_item_url, p.cart_item_seq2_item_brand, p.cart_item_seq2_low_stock,
  p.cart_item_seq3_image_url, p.cart_item_seq3_item_name, p.cart_item_seq3_item_url, p.cart_item_seq3_item_brand, p.cart_item_seq3_low_stock,
  p.cart_item_seq4_image_url, p.cart_item_seq4_item_name, p.cart_item_seq4_item_url, p.cart_item_seq4_item_brand, p.cart_item_seq4_low_stock,
  p.recommend_seq1_image_url, p.recommend_seq1_item_name, p.recommend_seq1_item_url, p.recommend_seq1_item_brand,
  p.recommend_seq2_image_url, p.recommend_seq2_item_name, p.recommend_seq2_item_url, p.recommend_seq2_item_brand,
  p.recommend_seq3_image_url, p.recommend_seq3_item_name, p.recommend_seq3_item_url, p.recommend_seq3_item_brand,
  p.recommend_seq4_image_url, p.recommend_seq4_item_name, p.recommend_seq4_item_url, p.recommend_seq4_item_brand,

  -- カート商品の価格情報（reco_product_stockから取得）
  COALESCE(FORMAT('%,d', TRY_CAST(sk1.taxin_price AS BIGINT)), '') AS cart_item_seq1_price,
  COALESCE(FORMAT('%,d', TRY_CAST(sk1.taxin_compare_at_price AS BIGINT)), '') AS cart_item_seq1_price_org,
  CASE WHEN sk1.sale_flag = '1' THEN '1' ELSE '' END AS cart_item_seq1_sale_flag,
  CASE WHEN sk1.sale_flag = '1' THEN COALESCE(sk1.discount_rate, '') ELSE '' END AS cart_item_seq1_discount_rate,
  COALESCE(FORMAT('%,d', TRY_CAST(sk2.taxin_price AS BIGINT)), '') AS cart_item_seq2_price,
  COALESCE(FORMAT('%,d', TRY_CAST(sk2.taxin_compare_at_price AS BIGINT)), '') AS cart_item_seq2_price_org,
  CASE WHEN sk2.sale_flag = '1' THEN '1' ELSE '' END AS cart_item_seq2_sale_flag,
  CASE WHEN sk2.sale_flag = '1' THEN COALESCE(sk2.discount_rate, '') ELSE '' END AS cart_item_seq2_discount_rate,
  COALESCE(FORMAT('%,d', TRY_CAST(sk3.taxin_price AS BIGINT)), '') AS cart_item_seq3_price,
  COALESCE(FORMAT('%,d', TRY_CAST(sk3.taxin_compare_at_price AS BIGINT)), '') AS cart_item_seq3_price_org,
  CASE WHEN sk3.sale_flag = '1' THEN '1' ELSE '' END AS cart_item_seq3_sale_flag,
  CASE WHEN sk3.sale_flag = '1' THEN COALESCE(sk3.discount_rate, '') ELSE '' END AS cart_item_seq3_discount_rate,
  COALESCE(FORMAT('%,d', TRY_CAST(sk4.taxin_price AS BIGINT)), '') AS cart_item_seq4_price,
  COALESCE(FORMAT('%,d', TRY_CAST(sk4.taxin_compare_at_price AS BIGINT)), '') AS cart_item_seq4_price_org,
  CASE WHEN sk4.sale_flag = '1' THEN '1' ELSE '' END AS cart_item_seq4_sale_flag,
  CASE WHEN sk4.sale_flag = '1' THEN COALESCE(sk4.discount_rate, '') ELSE '' END AS cart_item_seq4_discount_rate,

  -- レコメンド商品の価格情報
  COALESCE(FORMAT('%,d', TRY_CAST(rsk1.taxin_price AS BIGINT)), '') AS recommend_seq1_price,
  COALESCE(FORMAT('%,d', TRY_CAST(rsk1.taxin_compare_at_price AS BIGINT)), '') AS recommend_seq1_price_org,
  CASE WHEN rsk1.sale_flag = '1' THEN '1' ELSE '' END AS recommend_seq1_sale_flag,
  CASE WHEN rsk1.sale_flag = '1' THEN COALESCE(rsk1.discount_rate, '') ELSE '' END AS recommend_seq1_discount_rate,
  COALESCE(FORMAT('%,d', TRY_CAST(rsk2.taxin_price AS BIGINT)), '') AS recommend_seq2_price,
  COALESCE(FORMAT('%,d', TRY_CAST(rsk2.taxin_compare_at_price AS BIGINT)), '') AS recommend_seq2_price_org,
  CASE WHEN rsk2.sale_flag = '1' THEN '1' ELSE '' END AS recommend_seq2_sale_flag,
  CASE WHEN rsk2.sale_flag = '1' THEN COALESCE(rsk2.discount_rate, '') ELSE '' END AS recommend_seq2_discount_rate,
  COALESCE(FORMAT('%,d', TRY_CAST(rsk3.taxin_price AS BIGINT)), '') AS recommend_seq3_price,
  COALESCE(FORMAT('%,d', TRY_CAST(rsk3.taxin_compare_at_price AS BIGINT)), '') AS recommend_seq3_price_org,
  CASE WHEN rsk3.sale_flag = '1' THEN '1' ELSE '' END AS recommend_seq3_sale_flag,
  CASE WHEN rsk3.sale_flag = '1' THEN COALESCE(rsk3.discount_rate, '') ELSE '' END AS recommend_seq3_discount_rate,
  COALESCE(FORMAT('%,d', TRY_CAST(rsk4.taxin_price AS BIGINT)), '') AS recommend_seq4_price,
  COALESCE(FORMAT('%,d', TRY_CAST(rsk4.taxin_compare_at_price AS BIGINT)), '') AS recommend_seq4_price_org,
  CASE WHEN rsk4.sale_flag = '1' THEN '1' ELSE '' END AS recommend_seq4_sale_flag,
  CASE WHEN rsk4.sale_flag = '1' THEN COALESCE(rsk4.discount_rate, '') ELSE '' END AS recommend_seq4_discount_rate

FROM patterns p
CROSS JOIN recipients r
LEFT JOIN cart_abandonment_db.reco_product_stock sk1
  ON REGEXP_EXTRACT(p.cart_item_seq1_item_url, '/products/([^/?]+)', 1) = sk1.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock sk2
  ON REGEXP_EXTRACT(p.cart_item_seq2_item_url, '/products/([^/?]+)', 1) = sk2.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock sk3
  ON REGEXP_EXTRACT(p.cart_item_seq3_item_url, '/products/([^/?]+)', 1) = sk3.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock sk4
  ON REGEXP_EXTRACT(p.cart_item_seq4_item_url, '/products/([^/?]+)', 1) = sk4.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock rsk1
  ON REGEXP_EXTRACT(p.recommend_seq1_item_url, '/products/([^/?]+)', 1) = rsk1.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock rsk2
  ON REGEXP_EXTRACT(p.recommend_seq2_item_url, '/products/([^/?]+)', 1) = rsk2.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock rsk3
  ON REGEXP_EXTRACT(p.recommend_seq3_item_url, '/products/([^/?]+)', 1) = rsk3.item_id
LEFT JOIN cart_abandonment_db.reco_product_stock rsk4
  ON REGEXP_EXTRACT(p.recommend_seq4_item_url, '/products/([^/?]+)', 1) = rsk4.item_id
