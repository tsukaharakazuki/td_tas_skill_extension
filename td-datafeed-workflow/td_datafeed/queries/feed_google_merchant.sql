SELECT
    ec_sku_code AS id,
    title,
    CASE
        WHEN description IS NULL OR description = '' OR description = '\N'
        THEN CONCAT_WS('/', title, brand, gender, size, material)
        ELSE REGEXP_REPLACE(description, '<[^>]*>', '')
    END AS description,
    REPLACE(google_product_category, '>', ' > ') AS google_product_category,
    product_type,
    link,
    link AS mobile_link,
    image_link,
    CAST(NULL AS VARCHAR) AS additional_image_link,
    '${business.condition}' AS condition,
    CASE
        WHEN availability = 'pre_order' THEN 'preorder'
        ELSE availability
    END AS availability,
    CASE
        WHEN availability_date IS NOT NULL AND availability_date != '\N'
        THEN CONCAT(
            SUBSTR(CAST(availability_date AS VARCHAR), 1, 4), '-',
            SUBSTR(CAST(availability_date AS VARCHAR), 5, 2), '-',
            SUBSTR(CAST(availability_date AS VARCHAR), 7, 2),
            'T00:00:00${common.timezone_offset}'
        )
        ELSE NULL
    END AS availability_date,
    CONCAT(CAST(CAST(price_in_tax AS BIGINT) AS VARCHAR), ' ', '${common.currency_code}') AS price,
    CONCAT(CAST(CAST(sale_price_in_tax AS BIGINT) AS VARCHAR), ' ', '${common.currency_code}') AS sale_price,
    CASE
        WHEN sale_start_datetime IS NOT NULL AND sale_end_datetime IS NOT NULL
        THEN CONCAT(
            DATE_FORMAT(DATE_PARSE(sale_start_datetime, '%Y%m%d%H%i%s'), '%Y-%m-%dT%H:%i:%s${common.timezone_offset}'),
            '/',
            DATE_FORMAT(DATE_PARSE(sale_end_datetime, '%Y%m%d%H%i%s'), '%Y-%m-%dT%H:%i:%s${common.timezone_offset}')
        )
        ELSE NULL
    END AS sale_price_effective_date,
    CAST(NULL AS VARCHAR) AS gtin,
    ec_sku_code AS mpn,
    brand,
    CAST(NULL AS VARCHAR) AS identifier_exists,
    id AS item_group_id,
    color,
    CASE
        WHEN gender IS NULL OR gender = '' THEN '${common.default_gender}'
        WHEN gender = '\N' THEN 'unisex'
        ELSE gender
    END AS gender,
    '${business.age_group}' AS age_group,
    material,
    CAST(NULL AS VARCHAR) AS pattern,
    size,
    CASE WHEN title LIKE CONCAT('%', '${business.size_type_keyword}', '%')
         THEN '${business.matched_size_type}'
         ELSE '${business.default_size_type}'
    END AS size_type,
    '${business.size_system}' AS size_system,
    '${common.shipping_value}' AS shipping,
    CAST(NULL AS VARCHAR) AS shipping_weight,
    CASE
        WHEN CAST(sale_price_in_tax AS BIGINT) >= CAST('${rules.free_shipping_threshold}' AS BIGINT)
          OR CAST(price_in_tax AS BIGINT) >= CAST('${rules.free_shipping_threshold}' AS BIGINT)
        THEN '${business.free_shipping_label}'
        ELSE NULL
    END AS shipping_label,
    CAST(NULL AS VARCHAR) AS multipack,
    CAST(NULL AS VARCHAR) AS is_bundle,
    CAST(NULL AS VARCHAR) AS adult,
    CAST(NULL AS VARCHAR) AS ads_redirect,
    CAST(stock_quantity AS VARCHAR) AS custom_label_0,
    season AS custom_label_1,
    year AS custom_label_2,
    CAST(NULL AS VARCHAR) AS custom_label_3,
    CAST(NULL AS VARCHAR) AS custom_label_4,
    CAST(NULL AS VARCHAR) AS excluded_destination,
    CAST(NULL AS VARCHAR) AS expiration_date,
    CAST(NULL AS VARCHAR) AS loyalty_points,
    CAST(NULL AS VARCHAR) AS product_detail,
    CAST(NULL AS VARCHAR) AS product_highlight
FROM ${common.output_database}.datafeed_base
WHERE
    CAST(stock_quantity AS BIGINT) > CAST('${rules.minimum_stock}' AS BIGINT)
    AND google_product_category IS NOT NULL
    AND google_product_category != '\N'
    AND google_product_category != ''
    AND CAST(price_in_tax AS BIGINT) != 0
