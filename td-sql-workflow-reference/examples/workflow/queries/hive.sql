-- Used with td> engine: hive and create_table (or insert_into).
-- The write prefix belongs AFTER the CTE and BEFORE the final SELECT.
WITH samples AS (
  SELECT 'a.b' AS sample_text
)
-- DIGDAG_INSERT_LINE
SELECT
  CAST(1767225600 AS BIGINT) AS time,
  sample_text,
  sample_text RLIKE '\\.' AS has_literal_dot
FROM samples;
