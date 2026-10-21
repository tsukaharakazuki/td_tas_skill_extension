-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: qa | TD Trino syntax unverified.
-- Contract: exactly one row. hard_error_count > 0 must stop the run before 90_complete.
--   hard_errors is a numeric count; hard_error_codes / warnings are comma-joined codes.
--   Allowed by design (diagnostic only): multi-member sessions (MAX), zero purchases, unmatched orders,
--   cookie-missing web rows, purchase signals without order_id.
WITH w AS (
  SELECT
    COUNT(*) AS web_rows,
    MIN(event_time) AS web_min_event_time,
    MAX(event_time) AS web_max_event_time,
    COUNT(DISTINCT td_client_id) AS web_cookies,
    COUNT_IF(td_client_id IS NULL) AS web_cookie_missing_rows,
    COUNT_IF(event_time >= ${session_unixtime}) AS web_rows_at_or_after_cutoff,
    COUNT(*) - COUNT(DISTINCT event_key) AS web_duplicate_event_key_rows,
    COUNT_IF(td_client_id IS NOT NULL AND sdk_session_id IS NULL) AS sdk_session_missing_rows,
    COUNT_IF(is_purchase = 1 AND order_id IS NULL) AS purchase_signals_without_order_id,
    COUNT_IF(inflow_kind = 'unknown') AS unknown_inflow_rows,
    COUNT_IF(is_login = 1 AND member_id IS NULL) AS login_without_member_rows
  FROM ${td.database}.${table_prefix}_web_${session_unixtime}_${attempt_id}
),
es AS (
  SELECT
    COUNT(*) AS event_session_rows,
    COUNT_IF(raw_session_token IS NULL) AS event_session_null_token_rows
  FROM ${td.database}.${table_prefix}_event_sessions_${session_unixtime}_${attempt_id}
),
s AS (
  SELECT
    COUNT(*) AS sessions,
    COUNT(*) - COUNT(DISTINCT session_key) AS duplicate_session_keys,
    COUNT(DISTINCT td_client_id) AS session_cookies,
    COUNT_IF(member_id_count > 1) AS multi_member_sessions,
    COALESCE(SUM(event_count), 0) AS sessionized_events
  FROM ${td.database}.${table_prefix}_sessions_${session_unixtime}_${attempt_id}
),
mb AS (
  SELECT COUNT(*) AS member_observations, COUNT(DISTINCT td_client_id) AS member_observed_cookies
  FROM ${td.database}.${table_prefix}_members_${session_unixtime}_${attempt_id}
),
a AS (
  SELECT
    COUNT(*) AS acquisition_rows,
    COUNT(*) - COUNT(DISTINCT td_client_id) AS duplicate_acquisition_cookies,
    COUNT_IF(in_cohort = 1) AS cohort_cookies,
    MIN(acquisition_time) AS min_acquisition_time
  FROM ${td.database}.${table_prefix}_acquisition_${session_unixtime}_${attempt_id}
),
t AS (
  SELECT
    COUNT_IF(touch_mode = 'landing') AS landing_touches,
    COUNT_IF(touch_mode = 'session_inflow') AS session_inflow_touches
  FROM ${td.database}.${table_prefix}_touches_${session_unixtime}_${attempt_id}
),
r AS (
  SELECT
    COUNT(*) AS order_raw_rows,
    COUNT_IF(order_id IS NULL OR order_time IS NULL OR order_updated_time IS NULL) AS invalid_order_key_time_rows,
    COUNT_IF(currency IS NOT NULL AND currency <> '${currency}') AS order_currency_mismatch_rows,
    COUNT_IF(currency IS NULL) AS order_currency_missing_rows,
    COUNT_IF(order_updated_time < order_time) AS order_updated_before_order_rows,
    COUNT_IF(order_time >= ${session_unixtime} OR order_updated_time >= ${session_unixtime}) AS order_rows_at_or_after_cutoff,
    COUNT_IF(CAST(order_total AS DECIMAL(18, 2)) < 0) AS negative_total_rows
  FROM ${td.database}.${table_prefix}_order_raw_${session_unixtime}_${attempt_id}
),
o AS (
  SELECT
    COUNT(*) AS orders,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_orders,
    COUNT_IF(latest_conflict_variants > 1) AS orders_latest_conflict,
    COUNT_IF(snapshot_variants > 1) AS orders_snapshot_variants,
    COUNT_IF(snapshot_count > 1) AS orders_multi_snapshot,
    COUNT_IF(member_id IS NULL) AS orders_member_missing,
    COUNT_IF(order_total IS NULL) AS orders_unpriced
  FROM ${td.database}.${table_prefix}_orders_${session_unixtime}_${attempt_id}
),
oc AS (
  SELECT
    COUNT(*) AS order_credit_rows,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_credit,
    COUNT_IF(is_owned = 1) AS owned_orders,
    COUNT_IF(is_owned = 0) AS unmatched_orders,
    COUNT_IF(attribution_reason = 'unmatched_cookie_missing') AS unmatched_cookie_missing,
    COUNT_IF(attribution_reason = 'unmatched_member_missing') AS unmatched_member_missing,
    COUNT_IF(attribution_reason = 'unmatched_no_prior_member_observation') AS unmatched_no_prior_observation,
    COUNT_IF(is_owned = 1 AND member_observed_time >= order_time) AS owned_not_prior
  FROM ${td.database}.${table_prefix}_order_credit_${session_unixtime}_${attempt_id}
),
expected AS (
  SELECT
    COUNT(*) AS expected_cohort_orders,
    COALESCE(SUM(CAST(c.order_total AS DECIMAL(18, 2))), CAST(0 AS DECIMAL(18, 2))) AS expected_cohort_known_sales
  FROM ${td.database}.${table_prefix}_order_credit_${session_unixtime}_${attempt_id} c
  JOIN ${td.database}.${table_prefix}_acquisition_${session_unixtime}_${attempt_id} q
    ON q.td_client_id = c.owner_td_client_id
  WHERE c.is_owned = 1 AND q.in_cohort = 1
),
lb AS (
  SELECT
    COUNT(*) AS lookback_rows,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_lookback_orders,
    COUNT_IF(is_owned = 1 AND has_touch = 0) AS owned_orders_without_lookback_touch,
    COUNT_IF(has_touch = 1 AND touch_time >= order_time) AS lookback_touch_not_prior
  FROM ${td.database}.${table_prefix}_lookback_${session_unixtime}_${attempt_id}
),
co AS (
  SELECT
    COUNT(*) AS cohort_rows,
    COUNT(*) - COUNT(DISTINCT JSON_FORMAT(CAST(ARRAY[acquisition_date, source, medium, campaign, content, term, currency] AS JSON))) AS duplicate_cohort_grain,
    COALESCE(SUM(acquired_cookies), 0) AS cohort_acquired_cookies,
    COALESCE(SUM(orders), 0) AS cohort_orders,
    COALESCE(SUM(CAST(known_sales AS DECIMAL(18, 2))), CAST(0 AS DECIMAL(18, 2))) AS cohort_known_sales,
    COALESCE(SUM(CAST(spend AS DECIMAL(18, 2))), CAST(0 AS DECIMAL(18, 2))) AS cohort_spend,
    COUNT_IF(acquired_cookies = 0) AS spend_only_rows,
    COUNT_IF(roas_pct IS NULL) AS roas_null_rows
  FROM ${td.database}.${table_prefix}_cohort_${session_unixtime}_${attempt_id}
),
inf AS (
  SELECT
    COUNT(*) AS inflow_rows,
    COUNT(*) - COUNT(DISTINCT JSON_FORMAT(CAST(ARRAY[acquisition_date, source, medium, campaign, content, term, currency] AS JSON))) AS duplicate_inflow_grain
  FROM ${td.database}.${table_prefix}_inflow_${session_unixtime}_${attempt_id}
),
k AS (
  SELECT
    COUNT(*) AS cost_grain_rows,
    COALESCE(SUM(cost_rows), 0) AS cost_source_rows,
    COALESCE(SUM(null_spend_rows), 0) AS cost_null_spend_rows,
    COUNT_IF(currency IS NULL OR currency <> '${currency}') AS cost_currency_mismatch_rows,
    COUNT_IF(time IS NULL) AS cost_bad_date_rows,
    COUNT(*) - COUNT(DISTINCT JSON_FORMAT(CAST(ARRAY[cost_date, source, medium, campaign, content, term, currency] AS JSON))) AS duplicate_cost_grain,
    COALESCE(SUM(CAST(spend AS DECIMAL(18, 2))), CAST(0 AS DECIMAL(18, 2))) AS cost_spend
  FROM ${td.database}.${table_prefix}_costs_${session_unixtime}_${attempt_id}
),
z AS (
  SELECT *
  FROM w CROSS JOIN es CROSS JOIN s CROSS JOIN mb CROSS JOIN a CROSS JOIN t CROSS JOIN r CROSS JOIN o
       CROSS JOIN oc CROSS JOIN expected CROSS JOIN lb CROSS JOIN co CROSS JOIN inf CROSS JOIN k
),
f AS (
  SELECT
    z.*,
    FILTER(ARRAY[
      IF('${session_mode}' NOT IN ('sdk', 'window'), 'invalid_session_mode'),
      IF(web_rows = 0, 'web_empty'),
      IF(web_cookies = 0, 'web_has_no_valid_cookie'),
      IF(web_duplicate_event_key_rows > 0, 'conflicting_event_key_requires_review'),
      IF(web_rows_at_or_after_cutoff > 0, 'web_event_at_or_after_cutoff'),
      IF('${session_mode}' = 'sdk' AND sdk_session_missing_rows > 0, 'sdk_session_id_missing'),
      IF(duplicate_session_keys > 0, 'session_key_duplicate'),
      IF(sessionized_events <> event_session_rows - event_session_null_token_rows, 'session_event_count_mismatch'),
      IF(duplicate_acquisition_cookies > 0, 'acquisition_cookie_duplicate'),
      IF(acquisition_rows <> session_cookies, 'acquisition_cookie_universe_mismatch'),
      IF(landing_touches <> sessions, 'landing_touch_count_mismatch'),
      IF(order_currency_mismatch_rows > 0, 'order_currency_mismatch'),
      IF(order_currency_missing_rows > 0, 'order_currency_missing'),
      IF(order_rows_at_or_after_cutoff > 0, 'order_at_or_after_cutoff'),
      IF(duplicate_orders > 0, 'order_duplicate'),
      IF(invalid_order_key_time_rows > 0, 'order_required_key_or_time_missing'),
      IF(orders_latest_conflict > 0, 'order_latest_snapshot_conflict'),
      IF(duplicate_order_credit > 0 OR order_credit_rows <> orders, 'order_credit_not_one_per_order'),
      IF(owned_not_prior > 0, 'owner_observation_not_before_order'),
      IF(duplicate_lookback_orders > 0 OR lookback_rows <> orders, 'lookback_not_one_per_order'),
      IF(lookback_touch_not_prior > 0, 'lookback_touch_not_before_order'),
      IF(duplicate_cohort_grain > 0, 'cohort_grain_duplicate'),
      IF(cohort_acquired_cookies <> cohort_cookies, 'cohort_acquired_mismatch'),
      IF(cohort_orders <> expected_cohort_orders OR cohort_known_sales <> expected_cohort_known_sales, 'cohort_financial_base_mismatch'),
      IF(duplicate_inflow_grain > 0, 'inflow_grain_duplicate'),
      IF('${ad_costs_enabled}' = 'true' AND cost_currency_mismatch_rows > 0, 'cost_currency_mismatch'),
      IF('${ad_costs_enabled}' = 'true' AND cost_bad_date_rows > 0, 'cost_date_unparseable'),
      IF('${ad_costs_enabled}' = 'true' AND duplicate_cost_grain > 0, 'cost_grain_duplicate'),
      IF('${ad_costs_enabled}' = 'true' AND cohort_spend <> cost_spend, 'cost_spend_reconciliation_mismatch')
    ], x -> x IS NOT NULL) AS hard_error_list,
    FILTER(ARRAY[
      IF(web_cookie_missing_rows > 0, 'web_cookie_missing_rows'),
      IF('${session_mode}' = 'window' AND sdk_session_missing_rows > 0, 'sdk_session_id_missing_ignored_in_window_mode'),
      IF(web_duplicate_event_key_rows > 0, 'web_duplicate_event_key_rows'),
      IF(purchase_signals_without_order_id > 0, 'purchase_signals_without_order_id'),
      IF(unknown_inflow_rows > 0, 'unknown_inflow_rows'),
      IF(multi_member_sessions > 0, 'multi_member_sessions_max_selected'),
      IF(unmatched_orders > 0, 'unmatched_orders'),
      IF(orders_member_missing > 0, 'orders_member_missing'),
      IF(orders_unpriced > 0, 'orders_unpriced'),
      IF(order_currency_missing_rows > 0, 'order_currency_missing'),
      IF(orders_snapshot_variants > 0, 'order_snapshot_variants'),
      IF(order_updated_before_order_rows > 0, 'order_updated_before_order_time'),
      IF(negative_total_rows > 0, 'negative_order_totals'),
      IF('${ad_costs_enabled}' = 'true' AND cost_grain_rows = 0, 'costs_enabled_but_empty'),
      IF('${ad_costs_enabled}' = 'true' AND cost_null_spend_rows > 0, 'cost_null_spend_rows'),
      IF('${ad_costs_enabled}' = 'true' AND spend_only_rows > 0, 'cost_rows_without_acquisition')
    ], x -> x IS NOT NULL) AS warning_list
  FROM z
)
SELECT
  CARDINALITY(hard_error_list) AS hard_error_count,
  CARDINALITY(hard_error_list) AS hard_errors,
  ARRAY_JOIN(hard_error_list, ',') AS hard_error_codes,
  CARDINALITY(warning_list) AS warning_count,
  ARRAY_JOIN(warning_list, ',') AS warnings,
  '${session_mode}' AS session_mode,
  ${session_unixtime} AS cutoff_unixtime,
  web_rows, web_min_event_time, web_max_event_time, web_cookies, web_cookie_missing_rows,
  web_rows_at_or_after_cutoff, web_duplicate_event_key_rows, sdk_session_missing_rows,
  purchase_signals_without_order_id, unknown_inflow_rows, login_without_member_rows,
  event_session_rows, event_session_null_token_rows,
  sessions, duplicate_session_keys, session_cookies, multi_member_sessions, sessionized_events,
  member_observations, member_observed_cookies,
  acquisition_rows, duplicate_acquisition_cookies, cohort_cookies, min_acquisition_time,
  landing_touches, session_inflow_touches,
  order_raw_rows, invalid_order_key_time_rows, order_currency_mismatch_rows, order_currency_missing_rows,
  order_updated_before_order_rows, order_rows_at_or_after_cutoff, negative_total_rows,
  orders, duplicate_orders, orders_latest_conflict, orders_snapshot_variants, orders_multi_snapshot,
  orders_member_missing, orders_unpriced,
  order_credit_rows, duplicate_order_credit, owned_orders, unmatched_orders,
  unmatched_cookie_missing, unmatched_member_missing, unmatched_no_prior_observation, owned_not_prior,
  expected_cohort_orders, CAST(expected_cohort_known_sales AS VARCHAR) AS expected_cohort_known_sales,
  lookback_rows, duplicate_lookback_orders, owned_orders_without_lookback_touch, lookback_touch_not_prior,
  cohort_rows, duplicate_cohort_grain, cohort_acquired_cookies, cohort_orders,
  CAST(cohort_known_sales AS VARCHAR) AS cohort_known_sales, CAST(cohort_spend AS VARCHAR) AS cohort_spend,
  spend_only_rows, roas_null_rows,
  inflow_rows, duplicate_inflow_grain,
  cost_grain_rows, cost_source_rows, cost_null_spend_rows, cost_currency_mismatch_rows, cost_bad_date_rows,
  duplicate_cost_grain, CAST(cost_spend AS VARCHAR) AS cost_spend,
  ${session_unixtime} AS time
FROM f
