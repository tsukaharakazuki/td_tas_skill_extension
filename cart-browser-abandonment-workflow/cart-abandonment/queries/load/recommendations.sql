-- A complete recommendation snapshot per member; latest snapshot wins, even empty.
-- To invalidate an empty snapshot, emit a row with product_id NULL, available FALSE.
WITH snapshots AS (
  SELECT member_id, MAX(snapshot_at) AS snapshot_at
  FROM ${config.sources.recommendations} WHERE snapshot_at <= ${session_unixtime}
  GROUP BY member_id
), ranked AS (
  SELECT r.*, ROW_NUMBER() OVER (
    PARTITION BY r.member_id, r.product_id ORDER BY r.updated_at DESC, r.row_id DESC
  ) AS rn
  FROM ${config.sources.recommendations} r JOIN snapshots s
    ON r.member_id = s.member_id AND r.snapshot_at = s.snapshot_at
  WHERE r.updated_at <= ${session_unixtime}
)
SELECT member_id, product_id, position, item_name, item_url, image_url, brand,
       price, original_price, available
FROM ranked WHERE rn = 1
