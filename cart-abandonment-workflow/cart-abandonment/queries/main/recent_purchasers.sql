-- ============================================================
-- recent_purchasers.sql（カート放棄WF）
-- 直近48時間以内に注文したユーザーのハッシュemailリスト
--
-- 2026-07-18 新設（購買除外レイヤ2）:
--   Web Pixel の thank-you PV（レイヤ1・セッション単位除外）の
--   取りこぼしを補完するため、Shopify注文データ（毎朝06:30全量
--   スナップショット・前日23:59注文まで）でemail単位の除外を行う。
--   48時間は初期値。誤除外（購入直後の別商品カート放棄）との
--   トレードオフを見て 24h への短縮を検討する。
-- ============================================================

SELECT DISTINCT
  LOWER(TO_HEX(SHA256(CAST(email AS VARBINARY)))) AS hashed_email
FROM source_customer.orders
WHERE td_interval(time, '-3d/now')
  AND email IS NOT NULL
  AND email <> ''
  AND (cancelled_at IS NULL OR cancelled_at = '')
  AND TRY(TD_TIME_PARSE(created_at)) >= CAST(TO_UNIXTIME(NOW()) AS BIGINT) - 86400 * 2
