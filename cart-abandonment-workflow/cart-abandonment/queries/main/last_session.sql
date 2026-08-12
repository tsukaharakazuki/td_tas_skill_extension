-- ============================================================
-- last_session.sql（カート放棄WF）
-- ユーザー × セッションの最終アクセス時刻
-- ============================================================

SELECT
  user_id_comp,
  session_id,
  MAX(time) AS last_session_time,
  MAX(time) AS time
FROM cart_abandonment_db.cart_abandonment_cart_drop_weblog
GROUP BY user_id_comp, session_id
