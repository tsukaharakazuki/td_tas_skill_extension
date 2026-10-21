-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: cohort | TD Trino syntax unverified.
-- Contract: one row per acquisition_date x source x medium x campaign x content x term x currency
--   (first-session landing cohort, in_cohort only), FULL OUTER JOINed once with costs so spend-only rows remain.
--   acquired_cookies   = cookies whose first retained session is in [report_start, report_end)
--   logged_cookies     = of those, cookies with a member observation (at/after acquisition, up to cutoff);
--                        observed state, not necessarily a true login event
--   purchasing_cookies / orders / known_sales / unpriced_orders = owned orders credited to the cohort cookie
--   sales    = known_sales only when unpriced_orders = 0, else NULL
--   spend    = NULL when costs disabled or missing for the row
--   roas_pct = sales / spend * 100; NULL when any unpriced order, spend NULL or spend <= 0
--   Money columns are DECIMAL(18,2) rendered as VARCHAR. currency = pipeline currency (single-currency v1).
WITH a AS (
  SELECT *
  FROM ${td.database}.${table_prefix}_acquisition_${session_unixtime}_${attempt_id}
  WHERE in_cohort = 1
),
per_cookie AS (
  SELECT
    owner_td_client_id AS td_client_id,
    COUNT(*) AS orders,
    SUM(CAST(order_total AS DECIMAL(18, 2))) AS known_sales,
    COUNT_IF(order_total IS NULL) AS unpriced_orders
  FROM ${td.database}.${table_prefix}_order_credit_${session_unixtime}_${attempt_id}
  WHERE is_owned = 1
  GROUP BY owner_td_client_id
),
c AS (
  SELECT
    a.acquisition_date, a.source, a.medium, a.campaign, a.content, a.term,
    '${currency}' AS currency,
    COUNT(*) AS acquired_cookies,
    COUNT_IF(a.first_login_time IS NOT NULL) AS logged_cookies,
    COUNT_IF(p.orders > 0) AS purchasing_cookies,
    COALESCE(SUM(p.orders), 0) AS orders,
    COALESCE(SUM(p.known_sales), CAST(0 AS DECIMAL(18, 2))) AS known_sales,
    COALESCE(SUM(p.unpriced_orders), 0) AS unpriced_orders
  FROM a
  LEFT JOIN per_cookie p ON p.td_client_id = a.td_client_id
  GROUP BY a.acquisition_date, a.source, a.medium, a.campaign, a.content, a.term
),
k AS (
  SELECT
    cost_date, source, medium, campaign, content, term, currency,
    CAST(spend AS DECIMAL(18, 2)) AS spend
  FROM ${td.database}.${table_prefix}_costs_${session_unixtime}_${attempt_id}
  WHERE '${ad_costs_enabled}' = 'true'
),
j AS (
  SELECT
    COALESCE(c.acquisition_date, k.cost_date) AS acquisition_date,
    COALESCE(c.source, k.source) AS source,
    COALESCE(c.medium, k.medium) AS medium,
    COALESCE(c.campaign, k.campaign) AS campaign,
    COALESCE(c.content, k.content) AS content,
    COALESCE(c.term, k.term) AS term,
    COALESCE(c.currency, k.currency) AS currency,
    COALESCE(c.acquired_cookies, 0) AS acquired_cookies,
    COALESCE(c.logged_cookies, 0) AS logged_cookies,
    COALESCE(c.purchasing_cookies, 0) AS purchasing_cookies,
    COALESCE(c.orders, 0) AS orders,
    COALESCE(c.known_sales, CAST(0 AS DECIMAL(18, 2))) AS known_sales,
    COALESCE(c.unpriced_orders, 0) AS unpriced_orders,
    k.spend
  FROM c
  FULL OUTER JOIN k
    ON k.cost_date = c.acquisition_date
   AND k.source = c.source
   AND k.medium = c.medium
   AND k.campaign = c.campaign
   AND k.content = c.content
   AND k.term = c.term
   AND k.currency = c.currency
)
SELECT
  acquisition_date, source, medium, campaign, content, term, currency,
  acquired_cookies,
  logged_cookies,
  purchasing_cookies,
  orders,
  CAST(known_sales AS VARCHAR) AS known_sales,
  unpriced_orders,
  CAST(CASE WHEN unpriced_orders = 0 THEN known_sales END AS VARCHAR) AS sales,
  CAST(spend AS VARCHAR) AS spend,
  CASE WHEN unpriced_orders = 0 AND spend > 0
       THEN CAST(known_sales AS DOUBLE) / CAST(spend AS DOUBLE) * 100
  END AS roas_pct,
  TD_TIME_PARSE(acquisition_date, '${report_timezone}') AS time
FROM j
