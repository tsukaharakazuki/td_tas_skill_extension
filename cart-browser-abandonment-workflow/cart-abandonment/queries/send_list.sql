WITH contact_rows AS (
  SELECT NULLIF(TRIM(member_id), '') AS member_id, LOWER(TRIM(email)) AS email,
         consent, suppressed, updated_at, row_id
  FROM ${config.sources.recipients}
), invalid_members AS (
  -- A malformed opt-out cannot silently disappear from latest-row ordering.
  SELECT DISTINCT member_id FROM contact_rows
  WHERE updated_at IS NULL OR NULLIF(TRIM(row_id), '') IS NULL
), recipient_ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY updated_at DESC, row_id DESC) AS rn
  FROM contact_rows WHERE updated_at <= ${session_unixtime}
), recipient_latest AS (
  SELECT * FROM recipient_ranked WHERE rn = 1
), email_counts AS (
  SELECT email, COUNT(*) AS members FROM recipient_latest GROUP BY email
), recipients AS (
  -- Latest first, normalized email dedup, malformed or conflicting latest keys fail closed.
  SELECT r.member_id, r.email FROM recipient_latest r JOIN email_counts e ON r.email = e.email
  WHERE e.members = 1 AND r.consent = TRUE AND r.suppressed = FALSE
    AND NULLIF(TRIM(r.email), '') IS NOT NULL AND r.member_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM invalid_members b WHERE b.member_id = r.member_id)
    AND NOT EXISTS (
      SELECT 1 FROM contact_rows x
      WHERE x.member_id = r.member_id AND x.updated_at = r.updated_at AND x.row_id = r.row_id
        AND (COALESCE(x.email, '') <> COALESCE(r.email, '')
          OR COALESCE(CAST(x.consent AS VARCHAR), '') <> COALESCE(CAST(r.consent AS VARCHAR), '')
          OR COALESCE(CAST(x.suppressed AS VARCHAR), '') <> COALESCE(CAST(r.suppressed AS VARCHAR), ''))
    )
), history AS (
  SELECT member_id, kind, decision_id
  FROM ${config.sources.history}
  WHERE time >= CASE WHEN '${config.frequency.period}' = 'calendar_day'
    THEN TD_TIME_PARSE(TD_TIME_FORMAT(${session_unixtime}, 'yyyy-MM-dd', '${config.timezone}'), '${config.timezone}')
    ELSE ${session_unixtime} - ${config.frequency.window_seconds} END
    -- Later reservations also consume caps during delayed execution.
    AND status IN ('reserved', 'accepted', 'delivered')
), item_groups AS (
  SELECT member_id, kind, event_id, signal_time,
         MAX(CASE WHEN low_stock THEN 1 ELSE 0 END) AS has_low_stock,
         COALESCE(MAX(CASE WHEN item_no = 1 THEN CAST(product_id AS VARCHAR) END), '') AS item_1_product_id,
         COALESCE(MAX(CASE WHEN item_no = 1 THEN CAST(item_name AS VARCHAR) END), '') AS item_1_item_name,
         COALESCE(MAX(CASE WHEN item_no = 1 THEN CAST(item_url AS VARCHAR) END), '') AS item_1_item_url,
         COALESCE(MAX(CASE WHEN item_no = 1 THEN CASE WHEN image_url LIKE 'https://%' THEN image_url ELSE '' END END), '') AS item_1_image_url,
         COALESCE(MAX(CASE WHEN item_no = 1 THEN CAST(brand AS VARCHAR) END), '') AS item_1_brand,
         COALESCE(MAX(CASE WHEN item_no = 1 THEN CAST(price AS VARCHAR) END), '') AS item_1_price,
         COALESCE(MAX(CASE WHEN item_no = 1 THEN CAST(original_price AS VARCHAR) END), '') AS item_1_original_price,
         COALESCE(MAX(CASE WHEN item_no = 1 THEN CAST(quantity AS VARCHAR) END), '') AS item_1_quantity,
         COALESCE(MAX(CASE WHEN item_no = 1 THEN CASE WHEN low_stock THEN '1' ELSE '' END END), '') AS item_1_low_stock,
         COALESCE(MAX(CASE WHEN item_no = 2 THEN CAST(product_id AS VARCHAR) END), '') AS item_2_product_id,
         COALESCE(MAX(CASE WHEN item_no = 2 THEN CAST(item_name AS VARCHAR) END), '') AS item_2_item_name,
         COALESCE(MAX(CASE WHEN item_no = 2 THEN CAST(item_url AS VARCHAR) END), '') AS item_2_item_url,
         COALESCE(MAX(CASE WHEN item_no = 2 THEN CASE WHEN image_url LIKE 'https://%' THEN image_url ELSE '' END END), '') AS item_2_image_url,
         COALESCE(MAX(CASE WHEN item_no = 2 THEN CAST(brand AS VARCHAR) END), '') AS item_2_brand,
         COALESCE(MAX(CASE WHEN item_no = 2 THEN CAST(price AS VARCHAR) END), '') AS item_2_price,
         COALESCE(MAX(CASE WHEN item_no = 2 THEN CAST(original_price AS VARCHAR) END), '') AS item_2_original_price,
         COALESCE(MAX(CASE WHEN item_no = 2 THEN CAST(quantity AS VARCHAR) END), '') AS item_2_quantity,
         COALESCE(MAX(CASE WHEN item_no = 2 THEN CASE WHEN low_stock THEN '1' ELSE '' END END), '') AS item_2_low_stock,
         COALESCE(MAX(CASE WHEN item_no = 3 THEN CAST(product_id AS VARCHAR) END), '') AS item_3_product_id,
         COALESCE(MAX(CASE WHEN item_no = 3 THEN CAST(item_name AS VARCHAR) END), '') AS item_3_item_name,
         COALESCE(MAX(CASE WHEN item_no = 3 THEN CAST(item_url AS VARCHAR) END), '') AS item_3_item_url,
         COALESCE(MAX(CASE WHEN item_no = 3 THEN CASE WHEN image_url LIKE 'https://%' THEN image_url ELSE '' END END), '') AS item_3_image_url,
         COALESCE(MAX(CASE WHEN item_no = 3 THEN CAST(brand AS VARCHAR) END), '') AS item_3_brand,
         COALESCE(MAX(CASE WHEN item_no = 3 THEN CAST(price AS VARCHAR) END), '') AS item_3_price,
         COALESCE(MAX(CASE WHEN item_no = 3 THEN CAST(original_price AS VARCHAR) END), '') AS item_3_original_price,
         COALESCE(MAX(CASE WHEN item_no = 3 THEN CAST(quantity AS VARCHAR) END), '') AS item_3_quantity,
         COALESCE(MAX(CASE WHEN item_no = 3 THEN CASE WHEN low_stock THEN '1' ELSE '' END END), '') AS item_3_low_stock,
         COALESCE(MAX(CASE WHEN item_no = 4 THEN CAST(product_id AS VARCHAR) END), '') AS item_4_product_id,
         COALESCE(MAX(CASE WHEN item_no = 4 THEN CAST(item_name AS VARCHAR) END), '') AS item_4_item_name,
         COALESCE(MAX(CASE WHEN item_no = 4 THEN CAST(item_url AS VARCHAR) END), '') AS item_4_item_url,
         COALESCE(MAX(CASE WHEN item_no = 4 THEN CASE WHEN image_url LIKE 'https://%' THEN image_url ELSE '' END END), '') AS item_4_image_url,
         COALESCE(MAX(CASE WHEN item_no = 4 THEN CAST(brand AS VARCHAR) END), '') AS item_4_brand,
         COALESCE(MAX(CASE WHEN item_no = 4 THEN CAST(price AS VARCHAR) END), '') AS item_4_price,
         COALESCE(MAX(CASE WHEN item_no = 4 THEN CAST(original_price AS VARCHAR) END), '') AS item_4_original_price,
         COALESCE(MAX(CASE WHEN item_no = 4 THEN CAST(quantity AS VARCHAR) END), '') AS item_4_quantity,
         COALESCE(MAX(CASE WHEN item_no = 4 THEN CASE WHEN low_stock THEN '1' ELSE '' END END), '') AS item_4_low_stock
  FROM ${config.output.database}.${config.output.prefix}_items
  GROUP BY member_id, kind, event_id, signal_time
), rec_values AS (
  SELECT r.member_id, r.product_id, r.position,
    CASE WHEN ${config.personalization.products} THEN p.item_name ELSE r.item_name END AS item_name,
    CASE WHEN ${config.personalization.products} THEN p.item_url ELSE r.item_url END AS item_url,
    CASE WHEN ${config.personalization.products} THEN p.image_url ELSE r.image_url END AS image_url,
    CASE WHEN ${config.personalization.products} THEN p.brand ELSE r.brand END AS brand,
    CASE WHEN ${config.personalization.products} THEN p.price ELSE r.price END AS price,
    CASE WHEN ${config.personalization.products} THEN p.original_price ELSE r.original_price END AS original_price
  FROM ${config.output.database}.${config.output.prefix}_recommendations r
  LEFT JOIN ${config.output.database}.${config.output.prefix}_products p ON r.product_id = p.product_id
  WHERE r.available = TRUE AND NULLIF(TRIM(r.product_id), '') IS NOT NULL
    AND (NOT ${config.personalization.products} OR (p.available = TRUE AND p.published = TRUE))
    AND NOT EXISTS (SELECT 1 FROM ${config.output.database}.${config.output.prefix}_items i
                    WHERE i.member_id = r.member_id AND i.product_id = r.product_id)
), rec_ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY position, product_id) AS rec_no
  FROM rec_values WHERE item_url LIKE 'https://%' AND NULLIF(TRIM(item_name), '') IS NOT NULL
), rec_groups AS (
  SELECT member_id,
         COALESCE(MAX(CASE WHEN rec_no = 1 THEN CAST(product_id AS VARCHAR) END), '') AS recommend_1_product_id,
         COALESCE(MAX(CASE WHEN rec_no = 1 THEN CAST(item_name AS VARCHAR) END), '') AS recommend_1_item_name,
         COALESCE(MAX(CASE WHEN rec_no = 1 THEN CAST(item_url AS VARCHAR) END), '') AS recommend_1_item_url,
         COALESCE(MAX(CASE WHEN rec_no = 1 THEN CASE WHEN image_url LIKE 'https://%' THEN image_url ELSE '' END END), '') AS recommend_1_image_url,
         COALESCE(MAX(CASE WHEN rec_no = 1 THEN CAST(brand AS VARCHAR) END), '') AS recommend_1_brand,
         COALESCE(MAX(CASE WHEN rec_no = 1 THEN CAST(price AS VARCHAR) END), '') AS recommend_1_price,
         COALESCE(MAX(CASE WHEN rec_no = 1 THEN CAST(original_price AS VARCHAR) END), '') AS recommend_1_original_price,
         COALESCE(MAX(CASE WHEN rec_no = 2 THEN CAST(product_id AS VARCHAR) END), '') AS recommend_2_product_id,
         COALESCE(MAX(CASE WHEN rec_no = 2 THEN CAST(item_name AS VARCHAR) END), '') AS recommend_2_item_name,
         COALESCE(MAX(CASE WHEN rec_no = 2 THEN CAST(item_url AS VARCHAR) END), '') AS recommend_2_item_url,
         COALESCE(MAX(CASE WHEN rec_no = 2 THEN CASE WHEN image_url LIKE 'https://%' THEN image_url ELSE '' END END), '') AS recommend_2_image_url,
         COALESCE(MAX(CASE WHEN rec_no = 2 THEN CAST(brand AS VARCHAR) END), '') AS recommend_2_brand,
         COALESCE(MAX(CASE WHEN rec_no = 2 THEN CAST(price AS VARCHAR) END), '') AS recommend_2_price,
         COALESCE(MAX(CASE WHEN rec_no = 2 THEN CAST(original_price AS VARCHAR) END), '') AS recommend_2_original_price,
         COALESCE(MAX(CASE WHEN rec_no = 3 THEN CAST(product_id AS VARCHAR) END), '') AS recommend_3_product_id,
         COALESCE(MAX(CASE WHEN rec_no = 3 THEN CAST(item_name AS VARCHAR) END), '') AS recommend_3_item_name,
         COALESCE(MAX(CASE WHEN rec_no = 3 THEN CAST(item_url AS VARCHAR) END), '') AS recommend_3_item_url,
         COALESCE(MAX(CASE WHEN rec_no = 3 THEN CASE WHEN image_url LIKE 'https://%' THEN image_url ELSE '' END END), '') AS recommend_3_image_url,
         COALESCE(MAX(CASE WHEN rec_no = 3 THEN CAST(brand AS VARCHAR) END), '') AS recommend_3_brand,
         COALESCE(MAX(CASE WHEN rec_no = 3 THEN CAST(price AS VARCHAR) END), '') AS recommend_3_price,
         COALESCE(MAX(CASE WHEN rec_no = 3 THEN CAST(original_price AS VARCHAR) END), '') AS recommend_3_original_price,
         COALESCE(MAX(CASE WHEN rec_no = 4 THEN CAST(product_id AS VARCHAR) END), '') AS recommend_4_product_id,
         COALESCE(MAX(CASE WHEN rec_no = 4 THEN CAST(item_name AS VARCHAR) END), '') AS recommend_4_item_name,
         COALESCE(MAX(CASE WHEN rec_no = 4 THEN CAST(item_url AS VARCHAR) END), '') AS recommend_4_item_url,
         COALESCE(MAX(CASE WHEN rec_no = 4 THEN CASE WHEN image_url LIKE 'https://%' THEN image_url ELSE '' END END), '') AS recommend_4_image_url,
         COALESCE(MAX(CASE WHEN rec_no = 4 THEN CAST(brand AS VARCHAR) END), '') AS recommend_4_brand,
         COALESCE(MAX(CASE WHEN rec_no = 4 THEN CAST(price AS VARCHAR) END), '') AS recommend_4_price,
         COALESCE(MAX(CASE WHEN rec_no = 4 THEN CAST(original_price AS VARCHAR) END), '') AS recommend_4_original_price
  FROM rec_ranked WHERE rec_no <= 4 GROUP BY member_id
), decisions AS (
  SELECT i.*, CAST(LENGTH(i.member_id) AS VARCHAR) || ':' || i.member_id || ':' || i.kind || ':'
           || CAST(LENGTH(i.event_id) AS VARCHAR) || ':' || i.event_id AS decision_id
  FROM item_groups i
), permitted AS (
  SELECT i.*, r.email,
         ROW_NUMBER() OVER (PARTITION BY i.member_id ORDER BY CASE WHEN i.kind = 'cart' THEN 0 ELSE 1 END, i.signal_time DESC) AS priority
  FROM decisions i JOIN recipients r ON i.member_id = r.member_id
  WHERE NOT EXISTS (SELECT 1 FROM ${config.sources.history} prior WHERE prior.decision_id = i.decision_id)
    AND (SELECT COUNT(DISTINCT h.decision_id) FROM history h WHERE h.member_id = i.member_id) < ${config.frequency.total}
    AND (SELECT COUNT(DISTINCT h.decision_id) FROM history h WHERE h.member_id = i.member_id AND h.kind = i.kind) < ${config.frequency.per_kind}
)
SELECT ${session_unixtime} AS run_time, p.member_id, p.email, p.kind,
       p.decision_id,
       p.signal_time AS detected_at,
       CASE WHEN p.has_low_stock = 1 THEN 'low_stock' ELSE 'normal' END AS variant,
       COALESCE(CAST(a.points AS VARCHAR), '') AS points, COALESCE(a.segment, '') AS segment,
       COALESCE(c.code, '') AS coupon_code, COALESCE(c.description, '') AS coupon_description,
       CASE WHEN c.image_url LIKE 'https://%' THEN c.image_url ELSE '' END AS coupon_image_url,
       COALESCE(CAST(c.valid_until AS VARCHAR), '') AS coupon_valid_until,
       p.item_1_product_id,
       p.item_1_item_name,
       p.item_1_item_url,
       p.item_1_image_url,
       p.item_1_brand,
       p.item_1_price,
       p.item_1_original_price,
       p.item_1_quantity,
       p.item_1_low_stock,
       p.item_2_product_id,
       p.item_2_item_name,
       p.item_2_item_url,
       p.item_2_image_url,
       p.item_2_brand,
       p.item_2_price,
       p.item_2_original_price,
       p.item_2_quantity,
       p.item_2_low_stock,
       p.item_3_product_id,
       p.item_3_item_name,
       p.item_3_item_url,
       p.item_3_image_url,
       p.item_3_brand,
       p.item_3_price,
       p.item_3_original_price,
       p.item_3_quantity,
       p.item_3_low_stock,
       p.item_4_product_id,
       p.item_4_item_name,
       p.item_4_item_url,
       p.item_4_image_url,
       p.item_4_brand,
       p.item_4_price,
       p.item_4_original_price,
       p.item_4_quantity,
       p.item_4_low_stock,
       COALESCE(r.recommend_1_product_id, '') AS recommend_1_product_id,
       COALESCE(r.recommend_1_item_name, '') AS recommend_1_item_name,
       COALESCE(r.recommend_1_item_url, '') AS recommend_1_item_url,
       COALESCE(r.recommend_1_image_url, '') AS recommend_1_image_url,
       COALESCE(r.recommend_1_brand, '') AS recommend_1_brand,
       COALESCE(r.recommend_1_price, '') AS recommend_1_price,
       COALESCE(r.recommend_1_original_price, '') AS recommend_1_original_price,
       COALESCE(r.recommend_2_product_id, '') AS recommend_2_product_id,
       COALESCE(r.recommend_2_item_name, '') AS recommend_2_item_name,
       COALESCE(r.recommend_2_item_url, '') AS recommend_2_item_url,
       COALESCE(r.recommend_2_image_url, '') AS recommend_2_image_url,
       COALESCE(r.recommend_2_brand, '') AS recommend_2_brand,
       COALESCE(r.recommend_2_price, '') AS recommend_2_price,
       COALESCE(r.recommend_2_original_price, '') AS recommend_2_original_price,
       COALESCE(r.recommend_3_product_id, '') AS recommend_3_product_id,
       COALESCE(r.recommend_3_item_name, '') AS recommend_3_item_name,
       COALESCE(r.recommend_3_item_url, '') AS recommend_3_item_url,
       COALESCE(r.recommend_3_image_url, '') AS recommend_3_image_url,
       COALESCE(r.recommend_3_brand, '') AS recommend_3_brand,
       COALESCE(r.recommend_3_price, '') AS recommend_3_price,
       COALESCE(r.recommend_3_original_price, '') AS recommend_3_original_price,
       COALESCE(r.recommend_4_product_id, '') AS recommend_4_product_id,
       COALESCE(r.recommend_4_item_name, '') AS recommend_4_item_name,
       COALESCE(r.recommend_4_item_url, '') AS recommend_4_item_url,
       COALESCE(r.recommend_4_image_url, '') AS recommend_4_image_url,
       COALESCE(r.recommend_4_brand, '') AS recommend_4_brand,
       COALESCE(r.recommend_4_price, '') AS recommend_4_price,
       COALESCE(r.recommend_4_original_price, '') AS recommend_4_original_price
FROM permitted p
LEFT JOIN rec_groups r ON p.member_id = r.member_id
LEFT JOIN ${config.output.database}.${config.output.prefix}_attributes a ON p.member_id = a.member_id
LEFT JOIN ${config.output.database}.${config.output.prefix}_coupons c ON p.member_id = c.member_id
WHERE p.priority = 1
