-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: costs (ad_costs_enabled = false) | TD Trino syntax unverified.
-- Contract: same table name and columns as 00_costs.sql with zero rows, so spend stays NULL downstream.
SELECT
  CAST(NULL AS VARCHAR) AS cost_date,
  CAST(NULL AS VARCHAR) AS source,
  CAST(NULL AS VARCHAR) AS medium,
  CAST(NULL AS VARCHAR) AS campaign,
  CAST(NULL AS VARCHAR) AS content,
  CAST(NULL AS VARCHAR) AS term,
  CAST(NULL AS VARCHAR) AS currency,
  CAST(NULL AS VARCHAR) AS spend,
  CAST(0 AS BIGINT) AS cost_rows,
  CAST(0 AS BIGINT) AS null_spend_rows,
  CAST(NULL AS BIGINT) AS time
FROM (VALUES 1) AS t (x)
WHERE 1 = 0
