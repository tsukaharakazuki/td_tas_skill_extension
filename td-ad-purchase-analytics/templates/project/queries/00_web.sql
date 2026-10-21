-- Digdag td> create_table owns materialization; this file is SELECT only.
-- stage: web | ACTIVE ADAPTER (always runs). The validator must fail while any REPLACE_ME token remains.
-- TD Trino syntax: unverified (no runtime test available).
-- Contract: canonical input snapshot, materialized once. One row per retained raw web event with
--   event_time < cutoff (whole retained history; no report-window filter).
--   Flags are INTEGER 0/1 and money is an exact DECIMAL(18,2) rendered as VARCHAR,
--   because TD native table schemas have no BOOLEAN/DECIMAL column type. Readers CAST(... AS DECIMAL(18,2)).
-- Rows with a missing td_client_id / sdk_session_id are kept here so QA can count them before
--   sessionization discards them.
WITH src AS (
  SELECT
    -- event_time: epoch seconds of the actual event. If `time` is ingestion time, map the real event time here
    -- and keep the TD_TIME_RANGE partition cutoff below on `time`.
    CAST(time AS BIGINT) AS event_time,
    NULLIF(TRIM(CAST(td_client_id AS VARCHAR)), '') AS td_client_id,
    -- REPLACE_ME: verified member id expression (string). Compared as a string; session MAX uses string ordering.
    NULLIF(TRIM(CAST(REPLACE_ME_member_id_expr AS VARCHAR)), '') AS member_id,
    -- SDK session id column. Required only when session_mode = 'sdk' (NULL is a hard QA error in that mode).
    NULLIF(TRIM(CAST(NULL AS VARCHAR)), '') AS sdk_session_id,
    NULLIF(TRIM(CAST(td_url AS VARCHAR)), '') AS url,
    NULLIF(TRIM(CAST(td_referrer AS VARCHAR)), '') AS referrer,
    -- Optional dedicated UTM columns; NULL means "parse from url".
    NULLIF(TRIM(CAST(NULL AS VARCHAR)), '') AS utm_source_col,
    NULLIF(TRIM(CAST(NULL AS VARCHAR)), '') AS utm_medium_col,
    NULLIF(TRIM(CAST(NULL AS VARCHAR)), '') AS utm_campaign_col,
    NULLIF(TRIM(CAST(NULL AS VARCHAR)), '') AS utm_content_col,
    NULLIF(TRIM(CAST(NULL AS VARCHAR)), '') AS utm_term_col,
    -- REPLACE_ME: TRUE only for verified member/login observation
    -- (label it "member id observed" unless it is a real login-success event).
    CAST(REPLACE_ME_is_login_expr AS BOOLEAN) AS is_login_b,
    -- REPLACE_ME: ecommerce mapping. In purchase_mode=separate map these explicitly to FALSE / NULL.
    CAST(REPLACE_ME_is_purchase_expr AS BOOLEAN) AS is_purchase_b,
    NULLIF(TRIM(CAST(REPLACE_ME_order_id_expr AS VARCHAR)), '') AS order_id,
    TRY_CAST(REPLACE_ME_order_total_expr AS DECIMAL(18, 2)) AS order_total,
    NULLIF(UPPER(TRIM(CAST(REPLACE_ME_currency_expr AS VARCHAR))), '') AS currency,
    -- Stable native event id if the table has one; otherwise NULL -> deterministic canonical hash.
    NULLIF(TRIM(CAST(NULL AS VARCHAR)), '') AS native_event_id
  FROM ${web_table}
  WHERE TD_TIME_RANGE(time, NULL, ${session_unixtime})
),
parsed AS (
  SELECT
    s.*,
    NULLIF(TRY(url_extract_host(s.url)), '') AS url_host,
    NULLIF(LOWER(TRY(url_extract_host(s.referrer))), '') AS ref_host,
    COALESCE(s.utm_source_col,   NULLIF(TRIM(TRY(url_extract_parameter(s.url, 'utm_source'))), ''))   AS utm_source,
    COALESCE(s.utm_medium_col,   NULLIF(TRIM(TRY(url_extract_parameter(s.url, 'utm_medium'))), ''))   AS utm_medium,
    COALESCE(s.utm_campaign_col, NULLIF(TRIM(TRY(url_extract_parameter(s.url, 'utm_campaign'))), '')) AS utm_campaign,
    COALESCE(s.utm_content_col,  NULLIF(TRIM(TRY(url_extract_parameter(s.url, 'utm_content'))), ''))  AS utm_content,
    COALESCE(s.utm_term_col,     NULLIF(TRIM(TRY(url_extract_parameter(s.url, 'utm_term'))), ''))     AS utm_term
  FROM src s
  WHERE s.event_time IS NOT NULL
    AND s.event_time < ${session_unixtime}
),
classified AS (
  SELECT
    p.*,
    CASE
      WHEN p.utm_source IS NOT NULL THEN 'utm'
      WHEN p.url IS NOT NULL AND p.url_host IS NULL THEN 'unknown'           -- malformed page URL
      WHEN p.referrer IS NOT NULL AND p.ref_host IS NULL THEN 'unknown'      -- malformed referrer
      WHEN p.ref_host IS NOT NULL AND p.ref_host NOT IN ${internal_hosts_sql} THEN 'referral'
      WHEN p.ref_host IS NOT NULL THEN 'internal'                            -- exact internal host: not an inflow
      ELSE 'direct'
    END AS inflow_kind
  FROM parsed p
)
SELECT DISTINCT
  event_time,
  td_client_id,
  member_id,
  sdk_session_id,
  url,
  referrer,
  CASE inflow_kind WHEN 'utm' THEN utm_source WHEN 'referral' THEN ref_host WHEN 'unknown' THEN '(unknown)' ELSE '(direct)' END AS source,
  CASE inflow_kind WHEN 'utm' THEN COALESCE(utm_medium, '(not set)') WHEN 'referral' THEN 'referral' WHEN 'unknown' THEN '(unknown)' ELSE '(none)' END AS medium,
  CASE WHEN inflow_kind = 'utm' THEN COALESCE(utm_campaign, '(not set)') ELSE '(not set)' END AS campaign,
  CASE WHEN inflow_kind = 'utm' THEN COALESCE(utm_content, '(not set)') ELSE '(not set)' END AS content,
  CASE WHEN inflow_kind = 'utm' THEN COALESCE(utm_term, '(not set)') ELSE '(not set)' END AS term,
  CASE WHEN is_login_b THEN 1 ELSE 0 END AS is_login,
  CASE WHEN is_purchase_b THEN 1 ELSE 0 END AS is_purchase,
  order_id,
  CAST(order_total AS VARCHAR) AS order_total,
  currency,
  COALESCE(
    'n:' || native_event_id,
    'h:' || LOWER(TO_HEX(SHA256(TO_UTF8(JSON_FORMAT(CAST(ARRAY[
      CAST(event_time AS VARCHAR), td_client_id, member_id, sdk_session_id, url, referrer,
      utm_source, utm_medium, utm_campaign, utm_content, utm_term,
      CAST(is_login_b AS VARCHAR), CAST(is_purchase_b AS VARCHAR), order_id, CAST(order_total AS VARCHAR), currency
    ] AS JSON))))))
  ) AS event_key,
  CASE WHEN inflow_kind IN ('utm', 'referral', 'unknown') THEN 1 ELSE 0 END AS is_entry,
  inflow_kind,
  event_time AS time
FROM classified
