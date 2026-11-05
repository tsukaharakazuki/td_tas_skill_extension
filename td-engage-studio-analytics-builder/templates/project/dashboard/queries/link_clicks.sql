-- ダッシュボード用: メッセージ × リンク（メッセージごとにユニーククリック上位20件）
WITH agg AS (
  SELECT
    message_key,
    link_url,
    SUM(clicks)              AS clicks,
    SUM(unique_clicks)       AS unique_clicks,
    SUM(unique_clicks_human) AS unique_clicks_human
  FROM ${output_db}.${table_prefix}email_link_clicks
  WHERE send_date >= '${since_date}'
  GROUP BY 1, 2
)
SELECT message_key, link_url, clicks, unique_clicks, unique_clicks_human
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY message_key ORDER BY unique_clicks DESC, clicks DESC) AS rn
  FROM agg
)
WHERE rn <= 20
