-- Expired/revoked latest offer does NOT resurrect an older valid offer.
WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY updated_at DESC, row_id DESC) AS rn
  FROM ${config.sources.coupons} WHERE updated_at <= ${session_unixtime}
)
SELECT member_id, code, description, image_url, valid_until
FROM ranked WHERE rn = 1 AND active = TRUE
  AND valid_from <= ${session_unixtime} AND valid_until > ${session_unixtime}
