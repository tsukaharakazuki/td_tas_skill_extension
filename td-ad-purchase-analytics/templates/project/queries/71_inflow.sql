-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: inflow | TD Trino syntax unverified.
-- Contract: auxiliary, NON-ADDITIVE view. One row per acquisition_date x source x medium x campaign x content x term x currency.
--   Base = distinct (cohort cookie, source tuple) among first-session session_inflow touches, so a cookie appears once per
--   tuple but may appear under several tuples. associated_* are that cookie's owned orders (not credited to the tuple).
--   No spend / ROAS. Do not sum rows.
WITH a AS (
  SELECT td_client_id, acquisition_date, first_login_time
  FROM ${td.database}.${table_prefix}_acquisition_${session_unixtime}_${attempt_id}
  WHERE in_cohort = 1
),
t AS (
  SELECT DISTINCT td_client_id, source, medium, campaign, content, term
  FROM ${td.database}.${table_prefix}_touches_${session_unixtime}_${attempt_id}
  WHERE touch_mode = 'session_inflow'
    AND session_number = 1
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
x AS (
  SELECT
    a.acquisition_date, t.source, t.medium, t.campaign, t.content, t.term,
    a.td_client_id, a.first_login_time,
    COALESCE(p.orders, 0) AS orders,
    COALESCE(p.known_sales, CAST(0 AS DECIMAL(18, 2))) AS known_sales,
    COALESCE(p.unpriced_orders, 0) AS unpriced_orders
  FROM t
  JOIN a ON a.td_client_id = t.td_client_id
  LEFT JOIN per_cookie p ON p.td_client_id = t.td_client_id
)
SELECT
  acquisition_date, source, medium, campaign, content, term,
  '${currency}' AS currency,
  'nonadditive' AS additivity,
  COUNT(*) AS touched_new_cookies,
  COUNT_IF(first_login_time IS NOT NULL) AS logged_cookies,
  COUNT_IF(orders > 0) AS purchasing_cookies,
  SUM(orders) AS associated_orders,
  CAST(SUM(known_sales) AS VARCHAR) AS associated_known_sales,
  SUM(unpriced_orders) AS associated_unpriced_orders,
  CAST(CASE WHEN SUM(unpriced_orders) = 0 THEN SUM(known_sales) END AS VARCHAR) AS associated_sales,
  TD_TIME_PARSE(acquisition_date, '${report_timezone}') AS time
FROM x
GROUP BY acquisition_date, source, medium, campaign, content, term
