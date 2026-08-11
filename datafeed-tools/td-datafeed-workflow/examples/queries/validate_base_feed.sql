SELECT
    COUNT(*) AS row_count,
    SUM(CASE WHEN id IS NULL OR id = '' THEN 1 ELSE 0 END) AS missing_id,
    SUM(CASE WHEN ec_sku_code IS NULL OR ec_sku_code = '' THEN 1 ELSE 0 END) AS missing_sku,
    SUM(CASE WHEN price_in_tax IS NULL THEN 1 ELSE 0 END) AS missing_price,
    SUM(CASE WHEN link IS NULL OR link = '' THEN 1 ELSE 0 END) AS missing_link
FROM ${common.output_database}.datafeed_base
