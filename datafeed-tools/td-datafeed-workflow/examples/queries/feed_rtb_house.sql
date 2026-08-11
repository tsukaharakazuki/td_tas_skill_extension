-- RTB House DataFeed mapping sample.
-- Confirm the destination's current field names, XML/CSV schema, and transport requirements before use.
SELECT
    ec_sku_code AS id,
    title,
    CASE
        WHEN description IS NULL OR description = '' THEN CONCAT_WS('/', title, brand, gender, size, material)
        ELSE REGEXP_REPLACE(description, '<[^>]*>', '')
    END AS description,
    link,
    image_link,
    brand,
    product_type AS category,
    color,
    size,
    CONCAT(CAST(CAST(price_in_tax AS BIGINT) AS VARCHAR), ' ', '${common.currency_code}') AS price,
    CASE WHEN availability = 'pre_order' THEN 'preorder' ELSE availability END AS availability,
    '${business.condition}' AS condition,
    CAST(stock_quantity AS VARCHAR) AS stock_quantity,
    CAST(NULL AS VARCHAR) AS shipping_cost,
    CAST(NULL AS VARCHAR) AS sale_price,
    CAST(NULL AS VARCHAR) AS custom_label_0
FROM ${common.output_database}.datafeed_base
WHERE CAST(stock_quantity AS BIGINT) > CAST('${rules.minimum_stock}' AS BIGINT)
  AND link IS NOT NULL
  AND image_link IS NOT NULL
