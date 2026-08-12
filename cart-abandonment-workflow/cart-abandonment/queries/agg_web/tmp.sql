-- ============================================================
-- tmp.sql（カート放棄WF）
-- Weblogから必要カラムを抽出する前処理クエリ
--
-- 2026-07-18 改修（案A: リアルタイムソース切替）:
--   - ソース: l1_web.agg_weblog（日次バッチ・当日データなし）
--            → source_web_events（ほぼリアルタイム流入）
--   - 商品情報: items カラム（JSON配列文字列）を UNNEST で行展開
--     /cart ページはカート内全商品が1行1商品で得られる
--   - td_email: hashedmailaddress（= LOWER(HEX(SHA256(email)))）を使用
--   - 購買完了判定: Shopify Web Pixel の thank-you PV を ecommerce
--     カラムに 'purchase_thank_you' としてマーク
--     （旧設計の ecommerce カラムは常時空で機能していなかったため置換）
--   - bot除外条件は NULL セーフ化（Web Pixel行は td_user_agent 等が
--     NULL の場合があり、旧条件では購買シグナル行が落ちるため）
-- ============================================================

SELECT
  pv.time,
  'pageview'                                                                              AS td_data_type,
  IF(pv.td_ssc_id IS NULL OR pv.td_ssc_id = '', pv.td_client_id, pv.td_ssc_id)            AS cookie,
  IF(pv.td_ssc_id IS NULL OR pv.td_ssc_id = '', 'td_client_id', 'td_ssc_id')              AS cookie_type,
  pv.td_client_id,
  pv.td_global_id,
  pv.td_ssc_id                                                                            AS td_ssc_id,
  pv.hashedmailaddress                                                                    AS user_id,
  url_extract_parameter(pv.td_url, 'utm_campaign')                                        AS utm_campaign,
  url_extract_parameter(pv.td_url, 'utm_medium')                                          AS utm_medium,
  url_extract_parameter(pv.td_url, 'utm_source')                                          AS utm_source,
  url_extract_parameter(pv.td_url, 'utm_term')                                            AS utm_term,
  pv.td_referrer,
  url_extract_host(pv.td_referrer)                                                        AS td_ref_host,
  pv.td_url,
  url_extract_host(pv.td_url)                                                             AS td_host,
  url_extract_path(pv.td_url)                                                             AS td_path,
  pv.td_title,
  pv.td_description,
  pv.td_ip,
  pv.td_os,
  pv.td_user_agent,
  pv.td_browser,
  pv.td_screen,
  pv.td_viewport,
  element_at(TD_PARSE_AGENT(COALESCE(pv.td_user_agent, '')), 'os')         AS ua_os,
  element_at(TD_PARSE_AGENT(COALESCE(pv.td_user_agent, '')), 'vendor')     AS ua_vendor,
  element_at(TD_PARSE_AGENT(COALESCE(pv.td_user_agent, '')), 'os_version') AS ua_os_version,
  element_at(TD_PARSE_AGENT(COALESCE(pv.td_user_agent, '')), 'name')       AS ua_browser,
  element_at(TD_PARSE_AGENT(COALESCE(pv.td_user_agent, '')), 'category')   AS ua_category,
  TD_IP_TO_COUNTRY_NAME(pv.td_ip)                                          AS ip_country,
  TD_IP_TO_LEAST_SPECIFIC_SUBDIVISION_NAME(pv.td_ip)                       AS ip_prefectures,
  TD_IP_TO_CITY_NAME(pv.td_ip)                                             AS ip_city,
  -- カスタムカラム（items JSON配列を1行1商品に展開）
  json_extract_scalar(item, '$.item_id')                                   AS td_item_id,
  json_extract_scalar(item, '$.item_name')                                 AS td_item_name,
  json_extract_scalar(item, '$.item_category')                             AS td_item_category,
  json_extract_scalar(item, '$.price')                                     AS td_item_price,
  item_ord                                                                 AS td_item_ord,
  pv.hashedmailaddress                                                     AS td_email,
  -- 購買完了シグナル（Shopify Web Pixel thank-you ページ）
  CASE
    WHEN pv.td_path LIKE '%/checkouts/%thank-you'
      OR url_extract_path(pv.td_url) LIKE '%/checkouts/%thank-you'
    THEN 'purchase_thank_you'
  END                                                                      AS ecommerce
FROM source_web_events pv
LEFT JOIN UNNEST(COALESCE(TRY(CAST(json_parse(pv.items) AS ARRAY(JSON))), ARRAY[])) WITH ORDINALITY AS t(item, item_ord) ON TRUE
WHERE
  ${time_filter}
  AND COALESCE(element_at(TD_PARSE_AGENT(COALESCE(pv.td_user_agent, '')), 'category'), '') <> 'crawler'
  AND COALESCE(pv.td_client_id, '') <> '00000000-0000-4000-8000-000000000000'
  AND (pv.td_browser IS NULL
       OR NOT REGEXP_LIKE(pv.td_browser, '^(?:Googlebot(?:-.*)?|BingPreview|bingbot|YandexBot|PingdomBot)$'))
  AND pv.td_client_id IS NOT NULL
  AND pv.td_client_id <> 'undefined'
