-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: costs (ad_costs_enabled = true) | ADAPTER | TD Trino syntax unverified.
-- Active only when ad_costs_enabled = true: the validator must then fail on any REPLACE_ME token.
-- When disabled, run 00_costs_disabled.sql instead (same table/columns, zero rows) so 70_cohort/80_qa still resolve.
-- Contract: spend aggregated once at the cohort grain
--   cost_date ('yyyy-MM-dd' in report_timezone) x source x medium x campaign x content x term x currency,
--   restricted to report_start <= cost_date < report_end. Values must match web UTM values exactly (trim only, case-sensitive).
--   spend (DECIMAL(18,2) as VARCHAR) is NULL when any contributing row has an unparseable/missing spend.
--   Never spread coarser-grain spend (e.g. month x media) across days/campaigns here.
WITH src AS (
  SELECT
    NULLIF(TRIM(CAST(REPLACE_ME_cost_date_expr AS VARCHAR)), '') AS cost_date,
    COALESCE(NULLIF(TRIM(CAST(REPLACE_ME_source_expr AS VARCHAR)), ''), '(not set)') AS source,
    COALESCE(NULLIF(TRIM(CAST(REPLACE_ME_medium_expr AS VARCHAR)), ''), '(not set)') AS medium,
    COALESCE(NULLIF(TRIM(CAST(REPLACE_ME_campaign_expr AS VARCHAR)), ''), '(not set)') AS campaign,
    COALESCE(NULLIF(TRIM(CAST(REPLACE_ME_content_expr AS VARCHAR)), ''), '(not set)') AS content,
    COALESCE(NULLIF(TRIM(CAST(REPLACE_ME_term_expr AS VARCHAR)), ''), '(not set)') AS term,
    NULLIF(UPPER(TRIM(CAST(REPLACE_ME_currency_expr AS VARCHAR))), '') AS currency,
    TRY_CAST(REPLACE_ME_spend_expr AS DECIMAL(18, 2)) AS spend
  FROM REPLACE_ME_cost_database.REPLACE_ME_cost_table
)
SELECT
  cost_date,
  source, medium, campaign, content, term,
  currency,
  CAST(CASE WHEN COUNT_IF(spend IS NULL) = 0 THEN SUM(spend) END AS VARCHAR) AS spend,
  COUNT(*) AS cost_rows,
  COUNT_IF(spend IS NULL) AS null_spend_rows,
  TD_TIME_PARSE(cost_date, '${report_timezone}') AS time
FROM src
WHERE cost_date >= '${report_start}'
  AND cost_date < '${report_end}'
GROUP BY cost_date, source, medium, campaign, content, term, currency
