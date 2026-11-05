-- ダッシュボード用: LINE OA Insights 日別配信数（未設定ならテーブルは空）
SELECT date, status, broadcast, targeting, api_broadcast, api_push, api_multicast, total
FROM ${output_db}.${table_prefix}line_oa_daily
WHERE date >= '${since_date}'
