-- ============================================================
-- candidate_session.sql（カート放棄WF）
-- 候補セッションの特定: 直近 min_ago 分より前に終わったセッション
--
-- 「まだ閲覧中かもしれない」セッションを除外するため、
-- 最終アクセスが min_ago 分以上前のセッションのみを対象とする。
-- ============================================================

SELECT *
FROM cart_abandonment_db.cart_abandonment_last_session
WHERE
  TD_TIME_RANGE(
    time,
    NULL,
    CAST(TO_UNIXTIME(NOW()) AS BIGINT) - (60 * ${min_ago})
  )
