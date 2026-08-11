-- Generic BASE feed sample
--
-- This file is intentionally a sample, not a drop-in replacement for a client's
-- existing BASE SQL. Replace source roles, column mappings, URL expressions, and
-- business filters after reviewing BASE_FEED_SPEC.md and the target schema.
--
-- Required workflow variables are loaded from config/params.yml.

WITH latest_sku AS (
    SELECT
        sku.item_id,
        sku.item_code,
        sku.parent_item_id,
        sku.retail_price_out_tax,
        sku.retail_price_in_tax,
        sku.variation_name1,
        sku.variation_name2,
        sku.variation_id1,
        sku.register_date_time,
        sku.allocate_div,
        ROW_NUMBER() OVER (
            PARTITION BY sku.item_code
            ORDER BY sku.imported_at DESC
        ) AS rn
    FROM ${common.source_database}.${sources.sku_table} AS sku
    WHERE sku.status = 'ACTIVE'
),
item_master AS (
    SELECT
        item.item_id,
        item.item_code,
        item.item_name,
        item.merchant_item_code,
        item.brand_id,
        item.public_brand_id,
        item.category_id,
        ROW_NUMBER() OVER (
            PARTITION BY item.item_code
            ORDER BY item.imported_at DESC
        ) AS rn
    FROM ${common.source_database}.${sources.product_table} AS item
),
latest_description AS (
    SELECT
        description.item_id,
        description.description,
        ROW_NUMBER() OVER (
            PARTITION BY description.item_id
            ORDER BY description.imported_at DESC
        ) AS rn
    FROM ${common.source_database}.${sources.description_table} AS description
),
latest_sales AS (
    SELECT
        sales.item_id,
        sales.sales_start_datetime,
        sales.sales_end_datetime,
        sales.sale_price_out_tax,
        sales.sale_price_in_tax,
        sales.reserve_flag,
        sales.reserve_shipment_date,
        sales.publish_start_datetime,
        sales.publish_end_datetime,
        ROW_NUMBER() OVER (
            PARTITION BY sales.item_id
            ORDER BY sales.imported_at DESC
        ) AS rn
    FROM ${common.source_database}.${sources.sales_table} AS sales
    WHERE sales.store_id = '${common.store_id}'
      AND sales.sales_status = 'ACTIVE'
      AND sales.publish_flag = '1'
),
latest_stock AS (
    SELECT
        stock.item_id,
        stock.allocatable_stock,
        ROW_NUMBER() OVER (
            PARTITION BY stock.item_id
            ORDER BY stock.imported_at DESC
        ) AS rn
    FROM ${common.source_database}.${sources.stock_table} AS stock
    WHERE stock.location_id = '${common.stock_location_id}'
),
latest_stock_limit AS (
    SELECT
        stock_limit.item_id,
        stock_limit.sales_limit_amount,
        ROW_NUMBER() OVER (
            PARTITION BY stock_limit.item_id
            ORDER BY stock_limit.imported_at DESC
        ) AS rn
    FROM ${common.source_database}.${sources.stock_limit_table} AS stock_limit
),
brand_master AS (
    SELECT
        brand.brand_id,
        brand.brand_name,
        brand.brand_url_key,
        ROW_NUMBER() OVER (
            PARTITION BY brand.brand_id
            ORDER BY brand.imported_at DESC
        ) AS rn
    FROM ${common.source_database}.${sources.public_brand_table} AS brand
),
display_brand_master AS (
    SELECT
        brand.display_brand_id,
        brand.display_brand_name,
        ROW_NUMBER() OVER (
            PARTITION BY brand.display_brand_id
            ORDER BY brand.imported_at DESC
        ) AS rn
    FROM ${common.source_database}.${sources.display_brand_table} AS brand
),
category_master AS (
    SELECT
        category.category_id,
        category.google_product_category,
        category.product_type,
        ROW_NUMBER() OVER (
            PARTITION BY category.category_id
            ORDER BY category.imported_at DESC
        ) AS rn
    FROM ${common.category_master_table} AS category
),
joined_products AS (
    SELECT
        item.merchant_item_code AS product_code,
        item.item_code AS id,
        SUBSTR(item.item_code, 6, 2) AS year,
        SUBSTR(item.item_code, 8, 1) AS season,
        sku.retail_price_out_tax AS price_out_tax,
        sku.retail_price_in_tax AS price_in_tax,
        sales.sale_price_out_tax,
        sales.sale_price_in_tax,
        sales.sales_end_datetime AS sale_end_datetime,
        sales.sales_start_datetime AS sale_start_datetime,
        sku.variation_name1 AS color,
        sku.variation_name2 AS size,
        item.item_name AS title,
        item.brand_id AS brand_code,
        COALESCE(display_brand.display_brand_name, brand.brand_name) AS brand,
        brand.brand_url_key AS brand_abb,
        CAST(NULL AS VARCHAR) AS material,
        CAST(NULL AS VARCHAR) AS origin,
        CAST(NULL AS VARCHAR) AS gender,
        CASE
            WHEN CAST(sku.retail_price_in_tax AS DOUBLE) = 0 THEN 0
            ELSE ROUND(
                (1 - CAST(sales.sale_price_in_tax AS DOUBLE)
                    / CAST(sku.retail_price_in_tax AS DOUBLE)) * 100,
                -1
            )
        END AS discount_rate,
        description.description,
        CONCAT(
            '${common.product_url_prefix}',
            '/item/',
            item.item_code
        ) AS link,
        CASE
            WHEN sales.reserve_flag = '1' THEN sales.reserve_shipment_date
            ELSE NULL
        END AS availability_date,
        CONCAT(
            '${common.image_url_prefix}',
            '/item/',
            item.item_code,
            '/',
            sku.variation_id1,
            '.jpg'
        ) AS image_link,
        CASE
            WHEN sales.reserve_flag = '1' THEN 'pre_order'
            WHEN COALESCE(
                CASE
                    WHEN sku.allocate_div = 'LIMITED'
                        THEN stock_limit.sales_limit_amount
                    ELSE stock.allocatable_stock
                END,
                0
            ) >= CAST('${business.normal_minimum_stock}' AS BIGINT)
                THEN 'in_stock'
            ELSE NULL
        END AS availability,
        COALESCE(
            CASE
                WHEN sku.allocate_div = 'LIMITED'
                    THEN stock_limit.sales_limit_amount
                ELSE stock.allocatable_stock
            END,
            0
        ) AS stock_quantity,
        sales.item_id AS ec_sku_code,
        category.google_product_category,
        category.product_type,
        CAST(DATE_PARSE(sku.register_date_time, '%Y%m%d%H%i%s') AS VARCHAR) AS release_date,
        sales.publish_start_datetime,
        sales.publish_end_datetime
    FROM latest_sku AS sku
    INNER JOIN item_master AS item
        ON sku.parent_item_id = item.item_id
       AND item.rn = 1
    LEFT JOIN latest_description AS description
        ON item.item_id = description.item_id
       AND description.rn = 1
    LEFT JOIN latest_sales AS sales
        ON sku.item_id = sales.item_id
       AND sales.rn = 1
    LEFT JOIN latest_stock AS stock
        ON sku.item_id = stock.item_id
       AND stock.rn = 1
    LEFT JOIN latest_stock_limit AS stock_limit
        ON sku.item_id = stock_limit.item_id
       AND stock_limit.rn = 1
    LEFT JOIN brand_master AS brand
        ON item.public_brand_id = brand.brand_id
       AND brand.rn = 1
    LEFT JOIN display_brand_master AS display_brand
        ON item.brand_id = display_brand.display_brand_id
       AND display_brand.rn = 1
    LEFT JOIN category_master AS category
        ON item.category_id = category.category_id
       AND category.rn = 1
    WHERE sku.rn = 1
      AND item.item_name IS NOT NULL
      AND sales.sales_start_datetime IS NOT NULL
      AND sales.sales_end_datetime IS NOT NULL
),
visible_products AS (
    SELECT
        product_code,
        id,
        year,
        season,
        price_out_tax,
        price_in_tax,
        sale_price_out_tax,
        sale_price_in_tax,
        sale_end_datetime,
        sale_start_datetime,
        color,
        size,
        title,
        brand_code,
        brand,
        brand_abb,
        material,
        origin,
        gender,
        discount_rate,
        REGEXP_REPLACE(description, '[\\r\\n]', '') AS description,
        link,
        availability_date,
        image_link,
        availability,
        stock_quantity,
        ec_sku_code,
        google_product_category,
        product_type,
        release_date,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY stock_quantity DESC
        ) AS stock_quality_rank
    FROM joined_products
    WHERE (
            availability = 'in_stock'
            AND TD_TIME_FORMAT(TD_SCHEDULED_TIME(), 'yyyyMMddHHmmss', '${common.timezone_name}')
                BETWEEN sale_start_datetime AND sale_end_datetime
            AND TD_TIME_FORMAT(TD_SCHEDULED_TIME(), 'yyyyMMddHHmmss', '${common.timezone_name}')
                BETWEEN publish_start_datetime AND publish_end_datetime
        )
       OR (
            availability = 'pre_order'
            AND availability_date BETWEEN SUBSTR(sale_start_datetime, 1, 8)
                                      AND SUBSTR(sale_end_datetime, 1, 8)
        )
)
SELECT
    product_code,
    id,
    year,
    season,
    price_out_tax,
    price_in_tax,
    sale_price_out_tax,
    sale_price_in_tax,
    sale_end_datetime,
    sale_start_datetime,
    color,
    size,
    title,
    brand_code,
    brand,
    brand_abb,
    material,
    origin,
    gender,
    discount_rate,
    description,
    link,
    availability_date,
    image_link,
    availability,
    stock_quantity,
    ec_sku_code,
    google_product_category,
    product_type,
    release_date,
    CAST(NULL AS VARCHAR) AS novelty_flg,
    CASE WHEN stock_quality_rank = 1 THEN 1 ELSE 0 END AS is_max_stock_quality
FROM visible_products
