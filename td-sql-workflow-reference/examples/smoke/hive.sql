-- Read-only smoke query. Intended engine: TD Hive.
-- Expected: a.b => true, axb => false; wide_id => 2147483648.
-- Expected abc_hash => ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad.
-- The source SQL below contains two backslashes before the dot.
-- Engine execution has not been performed by the repository's local tests.
WITH samples AS (
  SELECT 'a.b' AS s
  UNION ALL
  SELECT 'axb' AS s
)
SELECT
  s,
  s RLIKE '\\.' AS has_literal_dot,
  CAST('2147483648' AS BIGINT) AS wide_id,
  CAST(NULL AS DECIMAL(18, 2)) AS nullable_amount,
  LOWER(SHA2('abc', 256)) AS abc_hash
FROM samples;
