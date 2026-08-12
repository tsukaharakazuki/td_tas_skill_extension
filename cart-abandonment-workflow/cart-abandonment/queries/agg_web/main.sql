-- ============================================================
-- main.sql（カート放棄WF）
-- セッション ID 付与・browsing_sec 計算・流入元分類
-- 参考WF（td_cart_drop）の main.sql をほぼそのまま移植
-- ============================================================

WITH t1 AS (
  SELECT
    time,
    td_data_type,
    TD_SESSIONIZE_WINDOW(time, ${session_span}) OVER (PARTITION BY cookie ORDER BY time) AS session_id,
    cookie,
    cookie_type,
    td_client_id,
    td_global_id,
    td_ssc_id,
    user_id,
    utm_campaign,
    utm_medium,
    utm_source,
    utm_term,
    CASE
      WHEN utm_source IS NOT NULL AND utm_medium IS NOT NULL
        THEN utm_source || '/' || utm_medium
      WHEN utm_source IS NOT NULL AND utm_medium IS NULL
        THEN utm_source || '/(none)'
      WHEN utm_source IS NULL AND utm_medium IS NOT NULL
        THEN '(none)/' || utm_medium
      WHEN REGEXP_LIKE(td_url, 'gclid')  THEN 'google/cpc'
      WHEN REGEXP_LIKE(td_url, 'fbclid') THEN 'facebook/ad'
      WHEN REGEXP_LIKE(td_url, 'yclid')  THEN 'yahoo/ad'
      WHEN REGEXP_LIKE(td_url, 'ldtag_cl') THEN 'line/ad'
      WHEN REGEXP_LIKE(td_url, 'twclid') THEN 'x/ad'
      WHEN REGEXP_LIKE(td_url, 'ttclid') THEN 'tiktok/ad'
      WHEN td_ref_host = '' OR td_ref_host = td_host OR td_ref_host IS NULL
        THEN '(direct)/(none)'
      WHEN REGEXP_LIKE(td_ref_host, '(mail)\.(google|yahoo|nifty|excite|ocn)\.')
        THEN CONCAT(REGEXP_EXTRACT(td_ref_host, '(mail)\.(google|yahoo|nifty|excite|ocn)\.', 2), '/mail')
      WHEN REGEXP_LIKE(td_ref_host, '\.*(facebook|instagram|line|ameblo)\.')
        THEN CONCAT(REGEXP_EXTRACT(td_ref_host, '\.*(facebook|instagram|line|ameblo)\.', 1), '/social')
      WHEN REGEXP_LIKE(td_ref_host, '(search)*\.*(google|yahoo|biglobe|goo|rakuten|docomo|naver)\.')
        THEN CONCAT(REGEXP_EXTRACT(td_ref_host, '(search)*\.*(google|yahoo|biglobe|goo|rakuten|docomo|naver)\.', 2), '/organic')
      ELSE CONCAT(td_ref_host, '/referral')
    END AS source_medium,
    td_referrer,
    td_ref_host,
    td_url,
    td_host,
    td_path,
    td_title,
    td_description,
    td_ip,
    td_os,
    td_user_agent,
    td_browser,
    td_screen,
    td_viewport,
    ua_os,
    ua_vendor,
    ua_os_version,
    ua_browser,
    ua_category,
    ip_country,
    ip_prefectures,
    ip_city
    ${(Object.prototype.toString.call(media[param].all_columns.columns) === '[object Array]')
      ? ',' + media[param].all_columns.columns.join() : ''}
  FROM cart_abandonment_db.cart_abandonment_tmp_cart_drop_weblog
)

SELECT
  time,
  '${media[param].media_name}'                                                          AS media_name,
  td_data_type,
  TD_TIME_FORMAT(time, 'yyyy-MM-dd HH:mm:ss', 'JST')                                   AS access_date_time,
  TD_TIME_FORMAT(time, 'yyyy-MM-dd', 'JST')                                             AS access_date,
  TD_TIME_FORMAT(time, 'HH', 'JST')                                                     AS access_hour,
  MIN(time) OVER (PARTITION BY session_id)                                              AS session_start_time,
  MAX(time) OVER (PARTITION BY session_id)                                              AS session_end_time,
  session_id,
  ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY time ASC)                         AS session_num,
  -- browsing_sec: 同セッション内の次のページ遷移までの秒数
  LEAD(time) OVER (PARTITION BY session_id ORDER BY time ASC) - time                   AS browsing_sec,
  cookie                                                                                 AS td_cookie,
  cookie_type                                                                            AS td_cookie_type,
  td_client_id,
  td_global_id,
  td_ssc_id,
  user_id,
  IF(user_id IS NULL,
     MAX(user_id) OVER (PARTITION BY session_id),
     user_id)                                                                            AS user_id_comp,
  utm_campaign,
  utm_medium,
  utm_source,
  utm_term,
  source_medium                                                                          AS td_source_medium,
  SPLIT(source_medium, '/')[1]                                                           AS td_source,
  SPLIT(source_medium, '/')[2]                                                           AS td_medium,
  td_referrer,
  td_ref_host,
  td_url,
  td_host || td_path                                                                     AS article_key,
  td_host,
  td_path,
  td_title,
  td_description,
  td_ip,
  td_os,
  td_user_agent,
  td_browser,
  td_screen,
  td_viewport,
  ua_os,
  ua_vendor,
  ua_os_version,
  ua_browser,
  ua_category,
  ip_country,
  REGEXP_REPLACE(REGEXP_REPLACE(ip_prefectures, '^Ō', 'O'), 'ō', 'o') AS ip_prefectures,
  REGEXP_REPLACE(REGEXP_REPLACE(ip_city, '^Ō', 'O'), 'ō', 'o')        AS ip_city,
  CAST(TO_UNIXTIME(NOW()) AS BIGINT)                                                     AS td_proc_date
  ${(Object.prototype.toString.call(media[param].all_columns.columns) === '[object Array]')
    ? ',' + media[param].all_columns.columns.join() : ''}
FROM t1
