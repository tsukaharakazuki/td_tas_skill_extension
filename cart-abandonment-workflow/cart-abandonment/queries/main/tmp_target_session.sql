-- ============================================================
-- tmp_target_session.sql（カート放棄WF）
-- 送信候補セッションの絞り込み
--
-- 処理:
--   候補セッション から 購買完了セッション を除外
--   さらに 除外メールリスト（customer社員等） に該当するユーザーを除外
--
-- 2026-07-18 改修:
--   - 購買除外レイヤ2を追加: 直近48h以内の注文者（cart_abandonment_recent_purchasers）
--     をemail単位で除外（Web Pixel購買シグナルの取りこぼし補完）
-- ============================================================

WITH

-- 候補セッション - 購買完了セッション
pickup AS (
  SELECT session_id FROM cart_abandonment_db.cart_abandonment_candidate_session
  EXCEPT
  SELECT session_id FROM cart_abandonment_db.cart_abandonment_purchase_session
)

SELECT a.*
FROM cart_abandonment_db.cart_abandonment_last_in_cart a
JOIN pickup b ON a.session_id = b.session_id
WHERE 1 = 1
  -- 除外ハッシュメールリスト（customer社員・テストアカウント）
  ${(Array.isArray(exclude_hashed_emails) && exclude_hashed_emails.length > 0)
    ? "AND a.user_id_comp NOT IN ('" + exclude_hashed_emails.join("','") + "')"
    : "-- exclude_hashed_emails が空のため除外なし"}
  -- 購買除外レイヤ2: 直近48h以内に注文があるユーザーを除外
  AND NOT EXISTS (
    SELECT 1 FROM cart_abandonment_db.cart_abandonment_recent_purchasers rp
    WHERE rp.hashed_email = a.user_id_comp
  )
  -- ------------------------------------------------------------------
  -- 地域除外レイヤ: 災害等により配信を停止している地域の会員を除外
  --   定義源は cart_abandonment_db.customer_suppression（create_crm_suppress.dig が作る）。
  --   地域の追加・解除はそのテーブルだけを直す。このSQLは触らない。
  --
  --   ★都道府県が不明な方は除外しない（customer様と合意した方針）。
  --     住所は配送実績がないと登録されないため、配信対象の約45%が不明。
  --     不明な方まで除外すると配信量が半減するため、分かる範囲での除外とする。
  --     → 取りこぼしが構造的に残ることをクライアントに報告済み。
  --
  --   ★突合キーは customer_identity_map.email（SHA256の16進小文字）。
  --     user_id_comp と同一形式であることを実測で確認済み（2,677名中2,609名=97.5%が突合）。
  -- ------------------------------------------------------------------
  AND NOT EXISTS (
    SELECT 1
    FROM cart_abandonment_db.customer_identity_map mc
    JOIN cart_abandonment_db.customer_suppression sr
      ON sr.prefecture = mc.prefectures
     AND sr.effective_to IS NULL          -- 解除済みの行は効かせない
    WHERE mc.email = a.user_id_comp
      -- ★NULL・空文字を「除外しない」ために明示的に弾いている（意図した挙動）。
      --   都道府県が不明な方は配信を続ける方針のため、
      --   この2行を外すと「不明な方も除外」に意味が変わってしまう。
      AND mc.prefectures IS NOT NULL
      AND mc.prefectures <> ''
  )
  -- ★不変条件の検証（2026-07-30 実測）:
  --   除外適用後の行数と人数が一致することを確認済み（2,562行 = 2,562名）。
  --   customer_identity_map.email は重複するが NOT EXISTS は存在判定のみなので行は増えない。
  --   同一人物で prefectures が食い違う email は 0 件（県の取り違えは起きない）。
