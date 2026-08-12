-- ============================================================
-- purchase_session.sql（カート放棄WF）
-- 購買完了セッションの特定（除外用）
--
-- customer site向け変更点:
--   参考WF: td_path = '/jp/ja/checkout/confirmation'
--   customer site: ecommerce カラムが IS NOT NULL の行を購買完了とみなす
--              （Weblog の GA4 dataLayer 経由で格納されるJSONデータ）
-- ============================================================

SELECT
  user_id_comp,
  session_id,
  MAX(time) AS last_purchase_time,
  MAX(time) AS time
FROM cart_abandonment_db.cart_abandonment_cart_drop_weblog
WHERE ecommerce IS NOT NULL
  AND ecommerce <> ''
GROUP BY user_id_comp, session_id
