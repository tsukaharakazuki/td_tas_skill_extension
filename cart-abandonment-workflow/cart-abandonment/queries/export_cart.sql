-- Frozen personalization, current consent, same-attempt reservation only.
-- Do not manually resume at export: replay within the SAME attempt is not exactly-once.
WITH contact_rows AS (
  SELECT NULLIF(TRIM(member_id), '') AS member_id, LOWER(TRIM(email)) AS email,
         consent, suppressed, updated_at, row_id
  FROM ${config.sources.recipients}
), invalid_members AS (
  SELECT DISTINCT member_id FROM contact_rows
  WHERE updated_at IS NULL OR NULLIF(TRIM(row_id), '') IS NULL
), current_ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY updated_at DESC, row_id DESC) AS rn
  FROM contact_rows WHERE updated_at <= CAST(TO_UNIXTIME(CURRENT_TIMESTAMP) AS BIGINT)
), current_latest AS (
  SELECT * FROM current_ranked WHERE rn = 1
), current_safe AS (
  SELECT r.* FROM current_latest r
  WHERE NOT EXISTS (SELECT 1 FROM invalid_members b WHERE b.member_id = r.member_id)
    AND NOT EXISTS (
      SELECT 1 FROM contact_rows x
      WHERE x.member_id = r.member_id AND x.updated_at = r.updated_at AND x.row_id = r.row_id
        AND (COALESCE(x.email, '') <> COALESCE(r.email, '')
          OR COALESCE(CAST(x.consent AS VARCHAR), '') <> COALESCE(CAST(r.consent AS VARCHAR), '')
          OR COALESCE(CAST(x.suppressed AS VARCHAR), '') <> COALESCE(CAST(r.suppressed AS VARCHAR), ''))
    )
)
SELECT p.email, p.kind, p.detected_at, p.variant, p.points, p.segment,
       p.coupon_code, p.coupon_description, p.coupon_image_url, p.coupon_valid_until,
       p.item_1_product_id, p.item_1_item_name, p.item_1_item_url, p.item_1_image_url,
       p.item_1_brand, p.item_1_price, p.item_1_original_price, p.item_1_quantity, p.item_1_low_stock,
       p.item_2_product_id, p.item_2_item_name, p.item_2_item_url, p.item_2_image_url,
       p.item_2_brand, p.item_2_price, p.item_2_original_price, p.item_2_quantity, p.item_2_low_stock,
       p.item_3_product_id, p.item_3_item_name, p.item_3_item_url, p.item_3_image_url,
       p.item_3_brand, p.item_3_price, p.item_3_original_price, p.item_3_quantity, p.item_3_low_stock,
       p.item_4_product_id, p.item_4_item_name, p.item_4_item_url, p.item_4_image_url,
       p.item_4_brand, p.item_4_price, p.item_4_original_price, p.item_4_quantity, p.item_4_low_stock,
       p.recommend_1_product_id, p.recommend_1_item_name, p.recommend_1_item_url, p.recommend_1_image_url,
       p.recommend_1_brand, p.recommend_1_price, p.recommend_1_original_price,
       p.recommend_2_product_id, p.recommend_2_item_name, p.recommend_2_item_url, p.recommend_2_image_url,
       p.recommend_2_brand, p.recommend_2_price, p.recommend_2_original_price,
       p.recommend_3_product_id, p.recommend_3_item_name, p.recommend_3_item_url, p.recommend_3_image_url,
       p.recommend_3_brand, p.recommend_3_price, p.recommend_3_original_price,
       p.recommend_4_product_id, p.recommend_4_item_name, p.recommend_4_item_url, p.recommend_4_image_url,
       p.recommend_4_brand, p.recommend_4_price, p.recommend_4_original_price
FROM ${config.output.database}.${config.output.prefix}_send_list p
WHERE p.run_time = ${session_unixtime} AND p.kind = 'cart'
  AND CAST(TO_UNIXTIME(CURRENT_TIMESTAMP) AS BIGINT) >= p.run_time
  AND CAST(TO_UNIXTIME(CURRENT_TIMESTAMP) AS BIGINT) - p.run_time <= ${config.workflow.max_execution_lag_seconds}
  AND EXISTS (SELECT 1 FROM ${config.sources.history} h
              WHERE h.decision_id = p.decision_id AND h.status = 'reserved'
                AND h.attempt_id = '${attempt_id}' AND h.time = p.run_time)
  AND EXISTS (SELECT 1 FROM current_safe r WHERE r.member_id = p.member_id
              AND r.email = p.email AND r.consent = TRUE AND r.suppressed = FALSE)
  AND NOT EXISTS (SELECT 1 FROM current_latest r WHERE r.email = p.email AND r.member_id <> p.member_id)
