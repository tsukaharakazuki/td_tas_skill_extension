WITH selected AS (
  SELECT c.member_id, c.kind, c.event_id, c.signal_time,
         e.product_id, e.quantity, e.item_position,
         CASE WHEN ${config.personalization.products} THEN p.item_name ELSE e.item_name END AS item_name,
         CASE WHEN ${config.personalization.products} THEN p.item_url ELSE e.item_url END AS item_url,
         CASE WHEN ${config.personalization.products} THEN p.image_url ELSE e.image_url END AS image_url,
         CASE WHEN ${config.personalization.products} THEN p.brand ELSE e.brand END AS brand,
         CASE WHEN ${config.personalization.products} THEN p.price ELSE e.price END AS price,
         CASE WHEN ${config.personalization.products} THEN p.original_price ELSE e.original_price END AS original_price,
         CASE WHEN ${config.personalization.products} THEN COALESCE(p.low_stock, FALSE) ELSE FALSE END AS low_stock
  FROM ${config.output.database}.${config.output.prefix}_candidates c
  JOIN ${config.output.database}.${config.output.prefix}_events e
    ON e.member_id = c.member_id AND e.event_id = c.event_id
  LEFT JOIN ${config.output.database}.${config.output.prefix}_products p ON p.product_id = e.product_id
  WHERE NULLIF(TRIM(e.product_id), '') IS NOT NULL
    AND (c.kind = 'browser' OR e.quantity > 0)
    AND (NOT ${config.personalization.products} OR (p.published = TRUE AND p.available = TRUE))
), ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY member_id, kind ORDER BY item_position, product_id) AS item_no
  FROM selected
  WHERE item_url LIKE 'https://%' AND NULLIF(TRIM(item_name), '') IS NOT NULL
)
SELECT * FROM ranked
WHERE item_no <= CASE WHEN kind = 'browser' THEN 1 ELSE ${config.personalization.max_items} END
