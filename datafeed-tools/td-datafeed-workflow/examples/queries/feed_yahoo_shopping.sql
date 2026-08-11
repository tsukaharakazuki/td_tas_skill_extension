-- Yahoo Shopping Ads feed mapping sample.
-- Confirm the applicable Yahoo Shopping Ads feed specification, field names,
-- encoding, delimiter, header, and upload method before use.
SELECT
    ec_sku_code AS item_id,
    title AS item_name,
    CASE
        WHEN description IS NULL OR description = '' THEN CONCAT_WS('/', title, brand, gender, size, material)
        ELSE REGEXP_REPLACE(description, '<[^>]*>', '')
    END AS item_description,
    link AS item_url,
    image_link AS image_url,
    brand,
    product_type AS category,
    color,
    size,
    CONCAT(CAST(CAST(price_in_tax AS BIGINT) AS VARCHAR), ' ', '${common.currency_code}') AS price,
    CASE WHEN availability = 'pre_order' THEN 'preorder' ELSE availability END AS availability,
    '${business.condition}' AS condition,
    CAST(stock_quantity AS VARCHAR) AS stock_quantity,
    CAST(NULL AS VARCHAR) AS sale_price,
    CAST(NULL AS VARCHAR) AS gtin,
    CAST(NULL AS VARCHAR) AS jan_code
FROM ${common.output_database}.datafeed_base
WHERE CAST(stock_quantity AS BIGINT) > CAST('${rules.minimum_stock}' AS BIGINT)
  AND link IS NOT NULL
  AND image_link IS NOT NULL
