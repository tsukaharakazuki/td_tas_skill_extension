-- ============================================================
-- create_push_send_list.sql（カート放棄WF・リアルタイム版）
-- Engage配信向け最終送信リスト生成
--
-- 設計方針:
--   推薦商品の計算はこのSQL内で完結する（毎日WFへの依存なし）。
--   依存する日次テーブル（毎日WFが生成）:
--     - cart_abandonment_db.reco_product_detail    （商品マスタ: 画像/URL/ブランド）
--     - cart_abandonment_db.reco_popularity_7d     （人気ランキング: new向け）
--     - cart_abandonment_db.reco_coview_30d        （co-view: f1/f2plus向け）
--     - cart_abandonment_db.reco_fbt_30d           （FBT: f1/f2plus向け）
--     - cart_abandonment_db.customer_identity_map      （email → td_llm_uid 変換）
--     - cart_abandonment_db.customer_order_history         （f1/f2plus: 前回購入商品）
--
-- セグメント別推薦ロジック:
--   unknown/f0: カート商品と同カテゴリの popularity_7d 上位4件
--   f1        : 前回購入商品の coview_30d → fbt_30d → popularity補完
--   f3plus    : 直近購入商品の fbt_30d（バスケット優先）→ coview → popularity補完
--
-- 2026-07-18 改修:
--   - 頻度キャップ導入（当日基準・JST）:
--       同種（カート放棄）: 1日1通まで（email単位、storeテーブル当日分で判定）
--       全体（カート+ブラウザ放棄合算）: 1日2通まで
--     ※従来の email×item 単位dedupを email×日 単位に強化
--   - reco_product_detail / customer_identity_map をdedupしてからJOIN
--     （重複行によるファンアウト防止: H-1/H-4対応）
--   - rfm_segment の集約を辞書順MAXから購買実績優先の優先度MAXに変更
-- ============================================================

WITH

-- 商品マスタのdedup（item_id重複によるファンアウト防止）
pd_dedup AS (
  SELECT
    item_id,
    MAX(item_name)  AS item_name,
    MAX(image_url)  AS image_url,
    MAX(item_url)   AS item_url,
    MAX(brand_name) AS brand_name
  FROM cart_abandonment_db.reco_product_detail
  GROUP BY item_id
),

-- email→uid 1:1 に正規化
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

-- 当日（JST）の送信済み履歴（カート放棄）
sent_today_cart AS (
  SELECT email, COUNT(*) AS cnt
  FROM cart_abandonment_db.cart_abandonment_store_cart_drop_sent_list_v2
  WHERE scheduled_time >= TD_TIME_FORMAT(
    TD_DATE_TRUNC('day', TD_SCHEDULED_TIME(), 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST')
  GROUP BY email
),

-- 当日（JST）の送信済み履歴（ブラウザ放棄）
sent_today_browser AS (
  SELECT email, COUNT(*) AS cnt
  FROM cart_abandonment_db.browser_abandonment_history
  WHERE scheduled_time >= TD_TIME_FORMAT(
    TD_DATE_TRUNC('day', TD_SCHEDULED_TIME(), 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST')
  GROUP BY email
),

-- ① 頻度キャップ適用後の配信候補
--    同種1日1通 + 全体（カート+ブラウザ）1日2通
dedup_emails AS (
  SELECT DISTINCT c.email
  FROM cart_abandonment_db.cart_abandonment_candidate_send_list c
  LEFT JOIN sent_today_cart    sc ON c.email = sc.email
  LEFT JOIN sent_today_browser sb ON c.email = sb.email
  WHERE c.seq_no = 1
    AND COALESCE(sc.cnt, 0) = 0                          -- 同種: 当日カート放棄配信なし
    AND COALESCE(sc.cnt, 0) + COALESCE(sb.cnt, 0) < 2    -- 全体: 当日合計2通未満
),

dedup AS (
  SELECT
    c.email,
    c.rfm_segment,
    c.last_item_id,
    c.last_item_name,
    c.last_item_category,
    c.seq_no
  FROM cart_abandonment_db.cart_abandonment_candidate_send_list c
  JOIN dedup_emails de ON c.email = de.email
),

-- ② カート商品のPIVOT（最大4件 → 横持ち）
cart_items_pivot AS (
  SELECT
    d.email,
    MAX(CASE WHEN d.seq_no = 1 THEN d.last_item_id END)       AS item_id_1,
    MAX(CASE WHEN d.seq_no = 1 THEN d.last_item_name END)     AS item_name_1,
    MAX(CASE WHEN d.seq_no = 1 THEN d.last_item_category END) AS item_category_1,
    MAX(CASE WHEN d.seq_no = 2 THEN d.last_item_id END)       AS item_id_2,
    MAX(CASE WHEN d.seq_no = 2 THEN d.last_item_name END)     AS item_name_2,
    MAX(CASE WHEN d.seq_no = 3 THEN d.last_item_id END)       AS item_id_3,
    MAX(CASE WHEN d.seq_no = 3 THEN d.last_item_name END)     AS item_name_3,
    MAX(CASE WHEN d.seq_no = 4 THEN d.last_item_id END)       AS item_id_4,
    MAX(CASE WHEN d.seq_no = 4 THEN d.last_item_name END)     AS item_name_4,
    -- セグメントは購買実績が多い解釈を優先（辞書順MAXでは 'unknown' が勝つため）
    CASE MAX(CASE d.rfm_segment
               WHEN 'f3plus' THEN 4 WHEN 'f1' THEN 3 WHEN 'f0' THEN 2 ELSE 1 END)
      WHEN 4 THEN 'f3plus' WHEN 3 THEN 'f1' WHEN 2 THEN 'f0' ELSE 'unknown'
    END AS rfm_segment
  FROM dedup d
  GROUP BY d.email
),

-- ③ カート商品の詳細情報（画像・URL・ブランド）- seq1用（従来互換 + 推薦ロジック用）
cart_with_product AS (
  SELECT
    cp.email,
    cp.rfm_segment,
    cp.item_id_1        AS last_item_id,
    cp.item_name_1      AS last_item_name,
    cp.item_category_1  AS last_item_category,
    pd1.image_url       AS cart_item_image_url,
    pd1.item_url        AS cart_item_url,
    pd1.brand_name      AS cart_item_brand,
    -- seq2
    cp.item_id_2,
    cp.item_name_2,
    pd2.image_url       AS cart_item_seq2_image_url,
    pd2.item_url        AS cart_item_seq2_item_url,
    pd2.brand_name      AS cart_item_seq2_brand,
    -- seq3
    cp.item_id_3,
    cp.item_name_3,
    pd3.image_url       AS cart_item_seq3_image_url,
    pd3.item_url        AS cart_item_seq3_item_url,
    pd3.brand_name      AS cart_item_seq3_brand,
    -- seq4
    cp.item_id_4,
    cp.item_name_4,
    pd4.image_url       AS cart_item_seq4_image_url,
    pd4.item_url        AS cart_item_seq4_item_url,
    pd4.brand_name      AS cart_item_seq4_brand
  FROM cart_items_pivot cp
  LEFT JOIN pd_dedup pd1 ON cp.item_id_1 = pd1.item_id
  LEFT JOIN pd_dedup pd2 ON cp.item_id_2 = pd2.item_id
  LEFT JOIN pd_dedup pd3 ON cp.item_id_3 = pd3.item_id
  LEFT JOIN pd_dedup pd4 ON cp.item_id_4 = pd4.item_id
),

-- ④ unknown/f0向け推薦: 同カテゴリのpopularity上位4件
reco_new AS (
  SELECT
    c.email,
    pd.image_url,
    pd.item_name,
    pd.item_url,
    pd.brand_name,
    ROW_NUMBER() OVER (PARTITION BY c.email ORDER BY pop.popularity_score DESC) AS seq_no
  FROM cart_with_product c
  JOIN cart_abandonment_db.reco_popularity_7d pop
    ON pop.item_category = c.last_item_category
    AND pop.item_id <> c.last_item_id
  JOIN pd_dedup pd
    ON pop.item_id = pd.item_id AND pd.image_url IS NOT NULL
  -- 在庫チェック: 在庫あり商品のみをレコメンド候補とする
  -- ⚠️ coview/fbt/popularity の基盤データには在庫フィルタを入れない（統計バイアス防止）
  JOIN cart_abandonment_db.reco_product_stock sk ON pop.item_id = sk.item_id AND sk.is_available = '1'
  WHERE c.rfm_segment IN ('unknown', 'f0')
),

-- ⑤ f1向け: 前回購入商品を特定（最新1件）
-- ⚠️ ID体系: coview は handle 軸、fbt は product_id 軸（item_b_handle が handle）
--    商品マスタ（reco_product_detail）は handle 軸のため、
--    coview には o.handle を、fbt には o.product_id を使い分ける（2026-07-18修正）
f1_last_purchase AS (
  SELECT email, last_purchase_product_id, last_purchase_handle
  FROM (
    SELECT
      c.email,
      o.product_id AS last_purchase_product_id,
      o.handle     AS last_purchase_handle,
      ROW_NUMBER() OVER (PARTITION BY c.email ORDER BY o.unixtime_created_at DESC) AS rn
    FROM cart_with_product c
    JOIN mjc_dedup mc ON c.email = mc.email
    JOIN cart_abandonment_db.customer_order_history o ON mc.td_llm_uid = o.td_llm_uid
    WHERE c.rfm_segment = 'f1'
      AND td_interval(o.unixtime_created_at, '-90d/now', 'JST')
      AND o.cancelled_at IS NULL
      AND o.handle IS NOT NULL AND o.handle <> ''
  )
  WHERE rn = 1
),

-- ⑤ f1推薦候補: coview + fbt + popularity（いずれも handle 軸に統一して出力）
f1_candidates AS (
  SELECT c.email, cv.item_b AS item_id, cv.co_view_sessions AS score, 1 AS pri
  FROM f1_last_purchase fp
  JOIN cart_with_product c ON fp.email = c.email
  JOIN cart_abandonment_db.reco_coview_30d cv ON fp.last_purchase_handle = cv.item_a
  WHERE cv.item_b <> c.last_item_id
  UNION ALL
  SELECT c.email, fbt.item_b_handle AS item_id, fbt.co_purchase_users AS score, 2 AS pri
  FROM f1_last_purchase fp
  JOIN cart_with_product c ON fp.email = c.email
  JOIN cart_abandonment_db.reco_fbt_30d fbt ON fp.last_purchase_product_id = fbt.item_a
  WHERE fbt.item_b_handle <> c.last_item_id
    AND fbt.item_b_handle IS NOT NULL AND fbt.item_b_handle <> ''
  UNION ALL
  SELECT c.email, pop.item_id, pop.popularity_score AS score, 3 AS pri
  FROM cart_with_product c
  JOIN cart_abandonment_db.reco_popularity_7d pop ON pop.item_category = c.last_item_category
  WHERE c.rfm_segment = 'f1' AND pop.item_id <> c.last_item_id
),

reco_f1 AS (
  SELECT email, image_url, item_name, item_url, brand_name, seq_no
  FROM (
    SELECT
      fc.email,
      pd.image_url, pd.item_name, pd.item_url, pd.brand_name,
      ROW_NUMBER() OVER (PARTITION BY fc.email ORDER BY fc.pri, fc.score DESC) AS seq_no,
      ROW_NUMBER() OVER (PARTITION BY fc.email, fc.item_id ORDER BY fc.pri)    AS dedup_rn
    FROM f1_candidates fc
    JOIN pd_dedup pd ON fc.item_id = pd.item_id AND pd.image_url IS NOT NULL
    -- 在庫チェック: 在庫あり商品のみ
    JOIN cart_abandonment_db.reco_product_stock sk ON fc.item_id = sk.item_id AND sk.is_available = '1'
  )
  WHERE dedup_rn = 1
),

-- ⑥ f3plus向け: 直近90日の購入商品（複数）
-- ⚠️ ID体系: fbt は product_id 軸、coview は handle 軸（2026-07-18修正）
f2plus_purchases AS (
  SELECT DISTINCT c.email, o.product_id AS purchased_product_id, o.handle AS purchased_handle
  FROM cart_with_product c
  JOIN mjc_dedup mc ON c.email = mc.email
  JOIN cart_abandonment_db.customer_order_history o ON mc.td_llm_uid = o.td_llm_uid
  WHERE c.rfm_segment = 'f3plus'
    AND td_interval(o.unixtime_created_at, '-90d/now', 'JST')
    AND o.cancelled_at IS NULL
    AND o.handle IS NOT NULL AND o.handle <> ''
),

-- ⑥ f3plus推薦候補: fbt優先（重み2倍）+ coview + popularity（handle 軸に統一して出力）
f2plus_candidates AS (
  SELECT c.email, fbt.item_b_handle AS item_id, fbt.co_purchase_users * 2 AS score, 1 AS pri
  FROM f2plus_purchases fp
  JOIN cart_with_product c ON fp.email = c.email
  JOIN cart_abandonment_db.reco_fbt_30d fbt ON fp.purchased_product_id = fbt.item_a
  WHERE fbt.item_b_handle <> c.last_item_id
    AND fbt.item_b_handle IS NOT NULL AND fbt.item_b_handle <> ''
  UNION ALL
  SELECT c.email, cv.item_b AS item_id, cv.co_view_sessions AS score, 2 AS pri
  FROM f2plus_purchases fp
  JOIN cart_with_product c ON fp.email = c.email
  JOIN cart_abandonment_db.reco_coview_30d cv ON fp.purchased_handle = cv.item_a
  WHERE cv.item_b <> c.last_item_id
  UNION ALL
  SELECT c.email, pop.item_id, pop.popularity_score AS score, 3 AS pri
  FROM cart_with_product c
  JOIN cart_abandonment_db.reco_popularity_7d pop ON pop.item_category = c.last_item_category
  WHERE c.rfm_segment = 'f3plus' AND pop.item_id <> c.last_item_id
),

reco_f2plus AS (
  SELECT email, image_url, item_name, item_url, brand_name, seq_no
  FROM (
    SELECT
      fc.email,
      pd.image_url, pd.item_name, pd.item_url, pd.brand_name,
      ROW_NUMBER() OVER (PARTITION BY fc.email ORDER BY fc.pri, fc.score DESC) AS seq_no,
      ROW_NUMBER() OVER (PARTITION BY fc.email, fc.item_id ORDER BY fc.pri)    AS dedup_rn
    FROM f2plus_candidates fc
    JOIN pd_dedup pd ON fc.item_id = pd.item_id AND pd.image_url IS NOT NULL
    -- 在庫チェック: 在庫あり商品のみ
    JOIN cart_abandonment_db.reco_product_stock sk ON fc.item_id = sk.item_id AND sk.is_available = '1'
  )
  WHERE dedup_rn = 1
),

-- ⑦ 全セグメント統合 → PIVOT（seq1〜4）
all_reco AS (
  SELECT email, image_url, item_name, item_url, brand_name, seq_no FROM reco_new    WHERE seq_no <= 4
  UNION ALL
  SELECT email, image_url, item_name, item_url, brand_name, seq_no FROM reco_f1     WHERE seq_no <= 4
  UNION ALL
  SELECT email, image_url, item_name, item_url, brand_name, seq_no FROM reco_f2plus WHERE seq_no <= 4
),

reco_pivot AS (
  SELECT
    email,
    MAX(CASE WHEN seq_no = 1 THEN image_url  END) AS seq1_image_url,
    MAX(CASE WHEN seq_no = 1 THEN item_name  END) AS seq1_item_name,
    MAX(CASE WHEN seq_no = 1 THEN item_url   END) AS seq1_item_url,
    MAX(CASE WHEN seq_no = 1 THEN brand_name END) AS seq1_item_brand,
    MAX(CASE WHEN seq_no = 2 THEN image_url  END) AS seq2_image_url,
    MAX(CASE WHEN seq_no = 2 THEN item_name  END) AS seq2_item_name,
    MAX(CASE WHEN seq_no = 2 THEN item_url   END) AS seq2_item_url,
    MAX(CASE WHEN seq_no = 2 THEN brand_name END) AS seq2_item_brand,
    MAX(CASE WHEN seq_no = 3 THEN image_url  END) AS seq3_image_url,
    MAX(CASE WHEN seq_no = 3 THEN item_name  END) AS seq3_item_name,
    MAX(CASE WHEN seq_no = 3 THEN item_url   END) AS seq3_item_url,
    MAX(CASE WHEN seq_no = 3 THEN brand_name END) AS seq3_item_brand,
    MAX(CASE WHEN seq_no = 4 THEN image_url  END) AS seq4_image_url,
    MAX(CASE WHEN seq_no = 4 THEN item_name  END) AS seq4_item_name,
    MAX(CASE WHEN seq_no = 4 THEN item_url   END) AS seq4_item_url,
    MAX(CASE WHEN seq_no = 4 THEN brand_name END) AS seq4_item_brand
  FROM all_reco
  GROUP BY email
)

-- ⑧ 最終出力（Engage HTMLのLiquid変数に対応）
SELECT
  c.email,
  c.rfm_segment                                            AS cart_abandon_rfm_segment,
  -- 従来互換カラム（seq1 = 最新カート商品）
  c.last_item_id                                           AS cart_abandon_item_id,
  c.last_item_name                                         AS cart_abandon_item_name,
  c.last_item_category                                     AS cart_abandon_item_category,
  c.cart_item_image_url                                    AS cart_abandon_image_url,
  c.cart_item_url                                          AS cart_abandon_item_url,
  c.cart_item_brand                                        AS cart_abandon_brand,
  -- カート商品 seq1（= 最新、従来互換と同じ内容）
  COALESCE(c.cart_item_image_url, '')                      AS cart_item_seq1_image_url,
  COALESCE(c.last_item_name, '')                           AS cart_item_seq1_item_name,
  COALESCE(c.cart_item_url, '')                            AS cart_item_seq1_item_url,
  COALESCE(c.cart_item_brand, '')                          AS cart_item_seq1_item_brand,
  -- カート商品 seq2
  COALESCE(c.cart_item_seq2_image_url, '')                 AS cart_item_seq2_image_url,
  COALESCE(c.item_name_2, '')                              AS cart_item_seq2_item_name,
  COALESCE(c.cart_item_seq2_item_url, '')                  AS cart_item_seq2_item_url,
  COALESCE(c.cart_item_seq2_brand, '')                     AS cart_item_seq2_item_brand,
  -- カート商品 seq3
  COALESCE(c.cart_item_seq3_image_url, '')                 AS cart_item_seq3_image_url,
  COALESCE(c.item_name_3, '')                              AS cart_item_seq3_item_name,
  COALESCE(c.cart_item_seq3_item_url, '')                  AS cart_item_seq3_item_url,
  COALESCE(c.cart_item_seq3_brand, '')                     AS cart_item_seq3_item_brand,
  -- カート商品 seq4
  COALESCE(c.cart_item_seq4_image_url, '')                 AS cart_item_seq4_image_url,
  COALESCE(c.item_name_4, '')                              AS cart_item_seq4_item_name,
  COALESCE(c.cart_item_seq4_item_url, '')                  AS cart_item_seq4_item_url,
  COALESCE(c.cart_item_seq4_brand, '')                     AS cart_item_seq4_item_brand,
  -- 推薦商品 seq1〜4（従来通り）
  COALESCE(r.seq1_image_url,  '')                          AS cart_abandon_recommend_seq1_image_url,
  COALESCE(r.seq1_item_name,  '')                          AS cart_abandon_recommend_seq1_item_name,
  COALESCE(r.seq1_item_url,   'https://example.com/cart')    AS cart_abandon_recommend_seq1_item_url,
  COALESCE(r.seq1_item_brand, '')                          AS cart_abandon_recommend_seq1_item_brand,
  COALESCE(r.seq2_image_url,  '')                          AS cart_abandon_recommend_seq2_image_url,
  COALESCE(r.seq2_item_name,  '')                          AS cart_abandon_recommend_seq2_item_name,
  COALESCE(r.seq2_item_url,   'https://example.com/cart')    AS cart_abandon_recommend_seq2_item_url,
  COALESCE(r.seq2_item_brand, '')                          AS cart_abandon_recommend_seq2_item_brand,
  COALESCE(r.seq3_image_url,  '')                          AS cart_abandon_recommend_seq3_image_url,
  COALESCE(r.seq3_item_name,  '')                          AS cart_abandon_recommend_seq3_item_name,
  COALESCE(r.seq3_item_url,   'https://example.com/cart')    AS cart_abandon_recommend_seq3_item_url,
  COALESCE(r.seq3_item_brand, '')                          AS cart_abandon_recommend_seq3_item_brand,
  COALESCE(r.seq4_image_url,  '')                          AS cart_abandon_recommend_seq4_image_url,
  COALESCE(r.seq4_item_name,  '')                          AS cart_abandon_recommend_seq4_item_name,
  COALESCE(r.seq4_item_url,   'https://example.com/cart')    AS cart_abandon_recommend_seq4_item_url,
  COALESCE(r.seq4_item_brand, '')                          AS cart_abandon_recommend_seq4_item_brand,
  TD_TIME_FORMAT(TD_SCHEDULED_TIME(), 'yyyy-MM-dd HH:mm:ss', 'JST') AS cart_abandon_detected_at
FROM cart_with_product c
LEFT JOIN reco_pivot r ON c.email = r.email
WHERE c.email IS NOT NULL
  AND c.email <> ''
