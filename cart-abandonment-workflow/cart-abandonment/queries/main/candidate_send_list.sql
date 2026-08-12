-- ============================================================
-- candidate_send_list.sql（カート放棄WF）
-- ユーザー別・最新セッションの放棄商品リスト（最大4件）+ RFMセグメント付与
--
-- 2026-07-18 改修:
--   - customer_identity_map は email 重複（1email→複数td_llm_uid）があるため
--     updated_at 最新の1行にdedupしてからJOIN（ファンアウト防止・H-1対応）
-- ============================================================

WITH

-- email→uid 1:1 に正規化（updated_at 最新を採用）
mjc_dedup AS (
  SELECT email, td_llm_uid
  FROM (
    SELECT
      email,
      td_llm_uid,
      ROW_NUMBER() OVER (
        PARTITION BY email
        ORDER BY COALESCE(TRY(TD_TIME_PARSE(updated_at)), 0) DESC, td_llm_uid
      ) AS rn
    FROM cart_abandonment_db.customer_identity_map
    WHERE email IS NOT NULL AND email <> ''
  )
  WHERE rn = 1
),

-- ユーザー別の最新セッションを特定
latest_session AS (
  SELECT
    user_id_comp,
    MAX_BY(session_id, time) AS session_id,
    MAX(time)                AS time
  FROM cart_abandonment_db.cart_abandonment_tmp_target_session
  WHERE user_id_comp IS NOT NULL
    AND user_id_comp <> ''
  GROUP BY user_id_comp
),

-- 最新セッションのカート商品（最大4件）を取得
latest_items AS (
  SELECT
    t.user_id_comp,
    t.time,
    t.session_id,
    t.last_item_id,
    t.last_item_name,
    t.last_item_category,
    t.last_item_price,
    t.seq_no
  FROM cart_abandonment_db.cart_abandonment_tmp_target_session t
  JOIN latest_session ls
    ON t.user_id_comp = ls.user_id_comp
    AND t.session_id = ls.session_id
  WHERE t.seq_no <= 4
)

SELECT
  l.user_id_comp                                          AS email,
  l.time,
  l.session_id,
  l.last_item_id,
  l.last_item_name,
  l.last_item_category,
  l.last_item_price,
  l.seq_no,
  -- RFMセグメント付与（4分割: unknown / f0 / f1 / f3plus）
  CASE
    WHEN r.td_llm_uid IS NULL   THEN 'unknown'   -- 購買履歴なし（未購入）
    WHEN r.frequency_all = 1    THEN 'f0'        -- 1回購入済み（→F1転換対象）
    WHEN r.frequency_all = 2    THEN 'f1'        -- 2回購入済み（→F2転換対象）
    ELSE                             'f3plus'    -- 3回以上購入
  END                                                     AS rfm_segment
FROM latest_items l
LEFT JOIN mjc_dedup c
  ON l.user_id_comp = c.email
LEFT JOIN cart_abandonment_db.customer_rfm r
  ON c.td_llm_uid = r.td_llm_uid
  AND r.brand = '<CUSTOMER_BRAND>'
