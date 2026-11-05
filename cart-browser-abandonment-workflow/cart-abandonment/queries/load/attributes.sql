WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY updated_at DESC, row_id DESC) AS rn
  FROM ${config.sources.attributes} WHERE updated_at <= ${session_unixtime}
)
SELECT member_id, points, segment FROM ranked WHERE rn = 1
