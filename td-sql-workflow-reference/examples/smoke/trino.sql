-- Read-only smoke query. Intended engine: TD Trino.
-- Expected: a.b => true, axb => false; wide_id => 2147483648.
-- Expected abc_hash => ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad.
-- Engine execution has not been performed by the repository's local tests.
WITH samples(s) AS (
  VALUES ('a.b'), ('axb')
)
SELECT
  s,
  regexp_like(s, '\.') AS has_literal_dot,
  CAST('2147483648' AS BIGINT) AS wide_id,
  CAST(NULL AS DECIMAL(18, 2)) AS nullable_amount,
  LOWER(TO_HEX(SHA256(TO_UTF8('abc')))) AS abc_hash
FROM samples;
