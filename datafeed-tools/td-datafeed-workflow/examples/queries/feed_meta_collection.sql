SELECT
    CONCAT(ec_sku_code, '_ad_', brand_abb, '_catalog') AS id,
    CASE WHEN availability = 'pre_order' THEN 'out of stock' ELSE availability END AS availability,
    '${business.condition}' AS condition,
    CASE
        WHEN description IS NULL OR description = '' OR description = '\N'
        THEN CONCAT_WS('/', title, brand, gender, size, material)
        ELSE REGEXP_REPLACE(description, '<[^>]*>', '')
    END AS description,
    image_link,
    CONCAT(link, '?utm_source=', '${channels.meta_collection.utm_source}', '&utm_medium=', '${channels.meta_collection.utm_medium}', '&utm_campaign=', brand_abb, '_', '${channels.meta_collection.utm_campaign_suffix}') AS link,
    title,
    CONCAT(CAST(CAST(price_in_tax AS BIGINT) AS VARCHAR), ' ', '${common.currency_code}') AS price,
    brand,
    CAST(NULL AS VARCHAR) AS gtin,
    ec_sku_code AS mpn,
    CAST(NULL AS VARCHAR) AS additional_image_link,
    'adult' AS age_group,
    color,
    CAST(NULL AS VARCHAR) AS expiration_date,
    CASE WHEN gender IS NULL OR gender = '' THEN '${common.default_gender}' ELSE gender END AS gender,
    id AS item_group_id,
    google_product_category,
    material,
    CAST(NULL AS VARCHAR) AS pattern,
    product_type,
    CASE
        WHEN CAST(sale_price_in_tax AS BIGINT) = CAST(price_in_tax AS BIGINT) THEN NULL
        ELSE CONCAT(CAST(CAST(sale_price_in_tax AS BIGINT) AS VARCHAR), ' ', '${common.currency_code}')
    END AS sale_price,
    CASE
        WHEN CAST(sale_price_in_tax AS BIGINT) = CAST(price_in_tax AS BIGINT) THEN NULL
        WHEN sale_start_datetime IS NOT NULL AND sale_end_datetime IS NOT NULL
        THEN CONCAT(DATE_FORMAT(DATE_PARSE(sale_start_datetime, '%Y%m%d%H%i%s'), '%Y-%m-%dT%H:%i:%s${common.timezone_offset}'), '/', DATE_FORMAT(DATE_PARSE(sale_end_datetime, '%Y%m%d%H%i%s'), '%Y-%m-%dT%H:%i:%s${common.timezone_offset}'))
        ELSE NULL
    END AS sale_price_effective_date,
    '${common.shipping_value}' AS shipping,
    CAST(NULL AS VARCHAR) AS shipping_weight,
    size,
    CAST(availability_date AS VARCHAR) AS custom_label_0,
    product_code AS custom_label_1,
    CAST(stock_quantity AS VARCHAR) AS custom_label_2,
    CAST(NULL AS VARCHAR) AS custom_label_3,
    CAST(NULL AS VARCHAR) AS custom_label_4
FROM ${common.output_database}.datafeed_base
WHERE
    CAST(year AS INTEGER) >= CAST('${rules.collection_min_year}' AS INTEGER)
