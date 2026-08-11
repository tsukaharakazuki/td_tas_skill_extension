-- Criteo Catalog feed mapping sample.
-- Confirm the official Criteo catalog schema and required transport format before use.
SELECT
    ec_sku_code AS id,
    title,
    CASE
        WHEN description IS NULL OR description = '' THEN CONCAT_WS('/', title, brand, gender, size, material)
        ELSE REGEXP_REPLACE(description, '<[^>]*>', '')
    END AS description,
    brand,
    product_type AS category,
    link,
    image_link,
    CASE WHEN availability = 'pre_order' THEN 'preorder' ELSE availability END AS availability,
    CONCAT(CAST(CAST(price_in_tax AS BIGINT) AS VARCHAR), ' ', '${common.currency_code}') AS price,
    CASE
        WHEN CAST(sale_price_in_tax AS BIGINT) = CAST(price_in_tax AS BIGINT) THEN NULL
        ELSE CONCAT(CAST(CAST(sale_price_in_tax AS BIGINT) AS VARCHAR), ' ', '${common.currency_code}')
    END AS sale_price,
    CAST(NULL AS VARCHAR) AS gtin,
    ec_sku_code AS mpn,
    id AS item_group_id,
    color,
    size,
    '${common.country_code}' AS country,
    '${business.condition}' AS condition,
    CAST(stock_quantity AS VARCHAR) AS custom_label_0
FROM ${common.output_database}.datafeed_base
WHERE CAST(stock_quantity AS BIGINT) > CAST('${rules.minimum_stock}' AS BIGINT)
  AND link IS NOT NULL
  AND image_link IS NOT NULL
