-- Latest row FIRST. An unavailable/unpublished newest row must block an old one.
WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY updated_at DESC, row_id DESC) AS rn
  FROM ${config.sources.products} WHERE updated_at <= ${session_unixtime}
)
SELECT product_id, item_name, item_url, image_url, brand, price, original_price,
       published, available, low_stock
FROM ranked WHERE rn = 1
