-- Used with td> engine: presto and create_table (or insert_into).
-- The marker is optional on Trino. If you keep it, it must stay BEFORE WITH.
-- DIGDAG_INSERT_LINE
WITH samples AS (
  SELECT 'a.b' AS sample_text
)
SELECT
  CAST(1767225600 AS BIGINT) AS time,
  sample_text,
  regexp_like(sample_text, '\.') AS has_literal_dot
FROM samples;
