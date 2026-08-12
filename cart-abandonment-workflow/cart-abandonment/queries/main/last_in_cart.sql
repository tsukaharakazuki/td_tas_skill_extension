-- ============================================================
-- last_in_cart.sql（カート放棄WF）
-- セッション内でカートに残っていた商品を最大4件取得（DISTINCT item_id）
--
-- 2026-07-18 改修:
--   - ソース切替（pageviews_rt）により /cart PV はカート内全商品が
--     1行1商品で展開される（td_item_ord = items配列内の順序）
--   - seq_no の順序を「最新PV → 配列順」で決定的にした
--     （seq_no=1 が最後にカートを見た時点の先頭商品）
-- ============================================================

SELECT
  user_id_comp,
  session_id,
  item_id       AS last_item_id,
  item_name     AS last_item_name,
  item_category AS last_item_category,
  item_price    AS last_item_price,
  time,
  seq_no
FROM (
  SELECT
    user_id_comp,
    session_id,
    item_id,
    item_name,
    item_category,
    item_price,
    time,
    -- セッション内で「最新PV→配列順」に番号付け（item_id重複排除済み）
    ROW_NUMBER() OVER (
      PARTITION BY user_id_comp, session_id
      ORDER BY time DESC, item_ord ASC
    ) AS seq_no
  FROM (
    SELECT
      user_id_comp,
      session_id,
      td_item_id       AS item_id,
      td_item_name     AS item_name,
      td_item_category AS item_category,
      CAST(td_item_price AS VARCHAR) AS item_price,
      td_item_ord      AS item_ord,
      time,
      -- item_id ごとに最新の行を残す（セッション内重複排除）
      ROW_NUMBER() OVER (
        PARTITION BY user_id_comp, session_id, td_item_id
        ORDER BY time DESC, td_item_ord ASC
      ) AS dedup_rn
    FROM cart_abandonment_db.cart_abandonment_cart_drop_weblog
    WHERE td_path = '/cart'
      AND td_item_id IS NOT NULL
      AND td_item_id <> ''
  )
  WHERE dedup_rn = 1
)
WHERE seq_no <= 4
