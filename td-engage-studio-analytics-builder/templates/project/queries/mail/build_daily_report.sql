-- =====================================================================
-- 日次メールレポートの本文（HTML部品）を作成
-- ---------------------------------------------------------------------
-- 結果は1行で、store_last_results により td.last_results.（列名）で
-- templates/mail_daily_report.html から参照されます
--   should_send  : 送信するか（前日の配信あり、または send_when_no_delivery = true）
--   subject      : 件名
--   report_date  : 対象日（実行日の前日）
--   kpi_html     : チャネル別KPI（前日 / 直近7日平均との比較）
--   trend_html   : 直近7日の日別推移
--   sent_html    : 前日に配信したメッセージ
--   top_html     : 直近7日に配信したメッセージ（累計の開封率・クリック率）
--   line_oa_html : LINE OA Insights の日別配信数（line.insights_enabled = true のとき）
--   greeting_html / dashboard_html : 宛名・ダッシュボードリンク（設定が空なら表示しない）
-- 配色は Treasure AI ブランド（td-tas-dashboard-template の --tas-* と同じHEX）
--   Primary 1 #494FFF / Primary 2 #8753FF / Accent 3 #EE2328（マイナス表示のみ）
-- =====================================================================
WITH

params AS (
  SELECT
    TD_TIME_STRING(TD_TIME_ADD(TD_DATE_TRUNC('day', ${session_unixtime}, '${tz}'), '-1d', '${tz}'), 'd!', '${tz}') AS d1,
    TD_TIME_STRING(TD_TIME_ADD(TD_DATE_TRUNC('day', ${session_unixtime}, '${tz}'), '-7d', '${tz}'), 'd!', '${tz}') AS d7,
    TD_TIME_STRING(TD_TIME_ADD(TD_DATE_TRUNC('day', ${session_unixtime}, '${tz}'), '-8d', '${tz}'), 'd!', '${tz}') AS d8
),

-- 日別 × チャネル（対象日を含む直近8日）
daily AS (
  SELECT
    d.channel,
    d.date,
    SUM(d.sent)                    AS sent,
    SUM(d.delivered)               AS delivered,
    SUM(d.failed)                  AS failed,
    SUM(d.opened)                  AS opened,
    SUM(d.clicked)                 AS clicked
  FROM ${output_db}.${table_prefix}daily d, params p
  WHERE d.date BETWEEN p.d8 AND p.d1
  GROUP BY 1, 2
),

-- チャネル別: 対象日 / 直近7日平均（対象日を除く）
kpi AS (
  SELECT
    c.channel,
    COALESCE(SUM(IF(d.date = p.d1, d.sent)), 0)      AS sent,
    COALESCE(SUM(IF(d.date = p.d1, d.delivered)), 0) AS delivered,
    COALESCE(SUM(IF(d.date = p.d1, d.failed)), 0)    AS failed,
    SUM(IF(d.date = p.d1, d.opened))                 AS opened,
    SUM(IF(d.date = p.d1, d.clicked))                AS clicked,
    COALESCE(SUM(IF(d.date < p.d1, d.sent)), 0) / 7.0 AS avg_sent
  FROM (SELECT 'email' AS channel WHERE ${email.enabled} UNION ALL SELECT 'line' WHERE ${line.enabled}) c
  CROSS JOIN params p
  LEFT JOIN daily d ON d.channel = c.channel
  GROUP BY 1
),

kpi_rows AS (
  SELECT
    channel,
    sent,
    '<tr>'
    || '<td style="padding:10px 12px;border-bottom:1px solid #E0E0E0;font-weight:600;white-space:nowrap;">' || IF(channel = 'email', 'メール', 'LINE') || '</td>'
    || '<td align="right" style="padding:10px 12px;border-bottom:1px solid #E0E0E0;font-family:Manrope,Arial,sans-serif;font-size:18px;font-weight:700;color:#494FFF;">' || FORMAT('%,d', sent)
    ||   '<br><span style="font-family:Inter,Arial,sans-serif;font-size:11px;font-weight:400;color:' || IF(sent < avg_sent, '#EE2328', '#666666') || ';">'
    ||   '7日平均 ' || FORMAT('%,.0f', avg_sent)
    ||   IF(avg_sent > 0, '（' || IF(sent >= avg_sent, '▲', '▼') || FORMAT('%.0f', ABS(sent - avg_sent) * 100.0 / avg_sent) || '%）', '')
    ||   '</span></td>'
    || '<td align="right" style="padding:10px 12px;border-bottom:1px solid #E0E0E0;">' || FORMAT('%,d', delivered)
    ||   IF(sent > 0, '<br><span style="font-size:11px;color:#666666;">' || FORMAT('%.1f', delivered * 100.0 / sent) || '%</span>', '') || '</td>'
    || '<td align="right" style="padding:10px 12px;border-bottom:1px solid #E0E0E0;">' || IF(opened IS NULL, '<span style="color:#999999;">—</span>', FORMAT('%,d', opened)) || '</td>'
    || '<td align="right" style="padding:10px 12px;border-bottom:1px solid #E0E0E0;">' || IF(clicked IS NULL, '<span style="color:#999999;">—</span>', FORMAT('%,d', clicked)) || '</td>'
    || '<td align="right" style="padding:10px 12px;border-bottom:1px solid #E0E0E0;color:' || IF(failed > 0, '#EE2328', '#000000') || ';">' || FORMAT('%,d', failed) || '</td>'
    || '</tr>' AS row_html
  FROM kpi
),

-- 直近7日の日別推移（全チャネル合計）
trend AS (
  SELECT
    d.date,
    SUM(d.sent)      AS sent,
    SUM(d.delivered) AS delivered,
    SUM(d.opened)    AS opened,
    SUM(d.clicked)   AS clicked,
    SUM(d.failed)    AS failed
  FROM daily d, params p
  WHERE d.date >= p.d7
  GROUP BY 1
),

trend_rows AS (
  SELECT
    date,
    '<tr>'
    || '<td style="padding:6px 8px;border-bottom:1px solid #E0E0E0;white-space:nowrap;">' || SUBSTR(date, 6) || '</td>'
    || '<td style="padding:6px 8px;border-bottom:1px solid #E0E0E0;width:45%;">'
    ||   '<div style="background-color:#EEF0FF;border-radius:4px;height:10px;"><div style="background-color:#494FFF;border-radius:4px;height:10px;width:'
    ||   CAST(GREATEST(CAST(ROUND(sent * 100.0 / NULLIF(MAX(sent) OVER (), 0)) AS INTEGER), IF(sent > 0, 2, 0)) AS VARCHAR) || '%;"></div></div></td>'
    || '<td align="right" style="padding:6px 8px;border-bottom:1px solid #E0E0E0;">' || FORMAT('%,d', sent) || '</td>'
    || '<td align="right" style="padding:6px 8px;border-bottom:1px solid #E0E0E0;">' || FORMAT('%,d', COALESCE(opened, 0)) || '</td>'
    || '<td align="right" style="padding:6px 8px;border-bottom:1px solid #E0E0E0;">' || FORMAT('%,d', COALESCE(clicked, 0)) || '</td>'
    || '<td align="right" style="padding:6px 8px;border-bottom:1px solid #E0E0E0;color:' || IF(failed > 0, '#EE2328', '#000000') || ';">' || FORMAT('%,d', failed) || '</td>'
    || '</tr>' AS row_html
  FROM trend
),

-- メッセージ表示用（HTMLエスケープ）
msg AS (
  SELECT
    s.*,
    REPLACE(REPLACE(REPLACE(SUBSTR(s.message_label, 1, 80), '&', '&amp;'), '<', '&lt;'), '>', '&gt;') AS h_label
  FROM ${output_db}.${table_prefix}message_summary s
),

-- 前日に配信したメッセージ（前日に送った通の、集計時点までの結果）
sent_msgs AS (
  SELECT
    c.channel,
    REPLACE(REPLACE(REPLACE(SUBSTR(c.message_label, 1, 80), '&', '&amp;'), '<', '&lt;'), '>', '&gt;') AS h_label,
    c.sent AS day_sent,
    ROUND(c.delivered * 100.0 / NULLIF(c.sent, 0), 1)    AS delivery_rate,
    ROUND(c.opened    * 100.0 / NULLIF(c.delivered, 0), 1) AS open_rate,
    ROUND(c.clicked   * 100.0 / NULLIF(c.delivered, 0), 1) AS click_rate
  FROM ${output_db}.${table_prefix}send_cohort c
  JOIN params p ON c.send_date = p.d1
  WHERE c.sent > 0
),

sent_rows AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY day_sent DESC, h_label) AS rn,
    '<tr>'
    || '<td style="padding:8px 10px;border-bottom:1px solid #E0E0E0;word-break:break-all;">'
    ||   '<span style="display:inline-block;padding:1px 8px;margin-right:6px;border-radius:8px;background-color:' || IF(channel = 'email', '#494FFF', '#8753FF') || ';color:#ffffff;font-size:11px;">' || IF(channel = 'email', 'Mail', 'LINE') || '</span>'
    ||   h_label || '</td>'
    || '<td align="right" style="padding:8px 10px;border-bottom:1px solid #E0E0E0;">' || FORMAT('%,d', day_sent) || '</td>'
    || '<td align="right" style="padding:8px 10px;border-bottom:1px solid #E0E0E0;">' || IF(delivery_rate IS NULL, '—', FORMAT('%.1f', delivery_rate) || '%') || '</td>'
    || '<td align="right" style="padding:8px 10px;border-bottom:1px solid #E0E0E0;">' || IF(open_rate IS NULL, '—', FORMAT('%.1f', open_rate) || '%') || '</td>'
    || '<td align="right" style="padding:8px 10px;border-bottom:1px solid #E0E0E0;">' || IF(click_rate IS NULL, '—', FORMAT('%.1f', click_rate) || '%') || '</td>'
    || '</tr>' AS row_html
  FROM sent_msgs
),

-- 直近7日に配信したメッセージ（累計の結果。遅れて届く開封・クリックも反映）
top_rows AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY m.sent DESC, m.h_label) AS rn,
    '<tr>'
    || '<td style="padding:8px 10px;border-bottom:1px solid #E0E0E0;word-break:break-all;">'
    ||   '<span style="display:inline-block;padding:1px 8px;margin-right:6px;border-radius:8px;background-color:' || IF(m.channel = 'email', '#494FFF', '#8753FF') || ';color:#ffffff;font-size:11px;">' || IF(m.channel = 'email', 'Mail', 'LINE') || '</span>'
    ||   m.h_label
    ||   '<br><span style="font-size:11px;color:#666666;">' || m.first_send_date || IF(m.last_send_date <> m.first_send_date, ' 〜 ' || m.last_send_date, '') || '</span></td>'
    || '<td align="right" style="padding:8px 10px;border-bottom:1px solid #E0E0E0;">' || FORMAT('%,d', m.sent) || '</td>'
    || '<td align="right" style="padding:8px 10px;border-bottom:1px solid #E0E0E0;">' || IF(m.open_rate IS NULL, '—', FORMAT('%.1f', m.open_rate) || '%') || '</td>'
    || '<td align="right" style="padding:8px 10px;border-bottom:1px solid #E0E0E0;">' || IF(m.click_rate IS NULL, '—', FORMAT('%.1f', m.click_rate) || '%') || '</td>'
    || '<td align="right" style="padding:8px 10px;border-bottom:1px solid #E0E0E0;color:' || IF(COALESCE(m.failure_rate, 0) >= 5, '#EE2328', '#000000') || ';">' || IF(m.failure_rate IS NULL, '—', FORMAT('%.1f', m.failure_rate) || '%') || '</td>'
    || '</tr>' AS row_html
  FROM msg m, params p
  WHERE m.last_send_date >= p.d7
),

-- LINE OA Insights（直近7日・確定前の日は status が ready 以外）
oa_rows AS (
  SELECT
    o.date,
    '<tr>'
    || '<td style="padding:6px 8px;border-bottom:1px solid #E0E0E0;">' || SUBSTR(o.date, 6) || IF(o.status <> 'ready', ' <span style="font-size:11px;color:#666666;">(未確定)</span>', '') || '</td>'
    || '<td align="right" style="padding:6px 8px;border-bottom:1px solid #E0E0E0;">' || FORMAT('%,d', o.api_push + o.api_multicast) || '</td>'
    || '<td align="right" style="padding:6px 8px;border-bottom:1px solid #E0E0E0;">' || FORMAT('%,d', o.broadcast + o.targeting + o.api_broadcast) || '</td>'
    || '<td align="right" style="padding:6px 8px;border-bottom:1px solid #E0E0E0;">' || FORMAT('%,d', o.total) || '</td>'
    || '</tr>' AS row_html
  FROM ${output_db}.${table_prefix}line_oa_daily o, params p
  WHERE ${line.insights_enabled} AND o.date >= p.d7
),

agg AS (
  SELECT
    (SELECT COALESCE(SUM(sent), 0) FROM kpi) AS total_sent,
    (SELECT ARRAY_JOIN(ARRAY_AGG(row_html ORDER BY channel), '') FROM kpi_rows) AS kpi_body,
    (SELECT ARRAY_JOIN(ARRAY_AGG(row_html ORDER BY date), '') FROM trend_rows) AS trend_body,
    (SELECT ARRAY_JOIN(ARRAY_AGG(row_html ORDER BY rn), '') FROM sent_rows WHERE rn <= ${mail_report.max_rows}) AS sent_body,
    (SELECT COUNT(1) FROM sent_rows) AS sent_count,
    (SELECT ARRAY_JOIN(ARRAY_AGG(row_html ORDER BY rn), '') FROM top_rows WHERE rn <= ${mail_report.max_rows}) AS top_body,
    (SELECT COUNT(1) FROM top_rows) AS top_count,
    (SELECT ARRAY_JOIN(ARRAY_AGG(row_html ORDER BY date), '') FROM oa_rows) AS oa_body
)

SELECT
  (a.total_sent > 0 OR ${mail_report.send_when_no_delivery}) AS should_send,
  '${mail_report.subject_brand} ${mail_report.title} ' || p.d1 || '（配信 ' || FORMAT('%,d', a.total_sent) || ' 通）' AS subject,
  p.d1 AS report_date,
  a.total_sent,

  -- 宛名・ダッシュボードリンク（config/mail_report.yml が空なら出さない）
  IF('${mail_report.account_label}' = '', '',
     '<p style="margin:0 0 4px 0;font-size:16px;font-weight:600;white-space:nowrap;">${mail_report.account_label} 様</p>') AS greeting_html,
  IF('${mail_report.dashboard_url}' = '', '',
     '<a href="${mail_report.dashboard_url}" target="_blank" style="display:inline-block;margin:0 0 20px 0;padding:10px 22px;border-radius:20px;background-color:#494FFF;color:#ffffff;font-size:14px;font-weight:600;text-decoration:none;">ダッシュボードを開く</a>') AS dashboard_html,

  -- チャネル別KPI
  '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-family:Inter,Arial,sans-serif;font-size:13px;color:#000000;">'
  || '<tr>'
  || '<th align="left"  style="background-color:#494FFF;color:#ffffff;padding:8px 12px;font-weight:600;white-space:nowrap;">チャネル</th>'
  || '<th align="right" style="background-color:#494FFF;color:#ffffff;padding:8px 12px;font-weight:600;white-space:nowrap;">配信</th>'
  || '<th align="right" style="background-color:#494FFF;color:#ffffff;padding:8px 12px;font-weight:600;white-space:nowrap;">到達</th>'
  || '<th align="right" style="background-color:#494FFF;color:#ffffff;padding:8px 12px;font-weight:600;white-space:nowrap;">開封</th>'
  || '<th align="right" style="background-color:#494FFF;color:#ffffff;padding:8px 12px;font-weight:600;white-space:nowrap;">クリック</th>'
  || '<th align="right" style="background-color:#494FFF;color:#ffffff;padding:8px 12px;font-weight:600;white-space:nowrap;">失敗</th>'
  || '</tr>' || COALESCE(a.kpi_body, '') || '</table>'
  || '<p style="margin:6px 0 0 0;font-size:11px;color:#666666;">開封・クリックは対象日に発生した通数（過去の配信分を含む）。メールの失敗はバウンス、LINEの失敗はAPIエラーです。LINEの開封・クリックは配信ログに含まれないため「—」です。</p>'
  AS kpi_html,

  -- 直近7日の推移
  CASE WHEN a.trend_body IS NULL THEN
    '<p style="margin:0;padding:14px;border:1px solid #E0E0E0;font-size:13px;color:#666666;text-align:center;">直近7日の配信はありません。</p>'
  ELSE
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-family:Inter,Arial,sans-serif;font-size:12px;color:#000000;">'
    || '<tr>'
    || '<th align="left"  style="padding:6px 8px;border-bottom:2px solid #494FFF;color:#494FFF;">日付</th>'
    || '<th align="left"  style="padding:6px 8px;border-bottom:2px solid #494FFF;color:#494FFF;">配信</th>'
    || '<th align="right" style="padding:6px 8px;border-bottom:2px solid #494FFF;color:#494FFF;">通数</th>'
    || '<th align="right" style="padding:6px 8px;border-bottom:2px solid #494FFF;color:#494FFF;">開封</th>'
    || '<th align="right" style="padding:6px 8px;border-bottom:2px solid #494FFF;color:#494FFF;">クリック</th>'
    || '<th align="right" style="padding:6px 8px;border-bottom:2px solid #494FFF;color:#494FFF;">失敗</th>'
    || '</tr>' || a.trend_body || '</table>'
  END AS trend_html,

  -- 前日に配信したメッセージ
  CASE WHEN a.sent_body IS NULL THEN
    '<p style="margin:0;padding:14px;border:1px solid #E0E0E0;font-size:13px;color:#666666;text-align:center;">' || p.d1 || ' の配信はありませんでした。</p>'
  ELSE
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-family:Inter,Arial,sans-serif;font-size:13px;color:#000000;">'
    || '<tr>'
    || '<th align="left"  style="background-color:#F5F5FF;padding:8px 10px;font-weight:600;white-space:nowrap;">メッセージ</th>'
    || '<th align="right" style="background-color:#F5F5FF;padding:8px 10px;font-weight:600;white-space:nowrap;">当日配信</th>'
    || '<th align="right" style="background-color:#F5F5FF;padding:8px 10px;font-weight:600;white-space:nowrap;">到達率</th>'
    || '<th align="right" style="background-color:#F5F5FF;padding:8px 10px;font-weight:600;white-space:nowrap;">開封率</th>'
    || '<th align="right" style="background-color:#F5F5FF;padding:8px 10px;font-weight:600;white-space:nowrap;">クリック率</th>'
    || '</tr>' || a.sent_body || '</table>'
    || IF(a.sent_count > ${mail_report.max_rows}, '<p style="margin:6px 0 0 0;font-size:12px;color:#666666;">ほか ' || CAST(a.sent_count - ${mail_report.max_rows} AS VARCHAR) || ' 件はダッシュボードで確認できます。</p>', '')
  END AS sent_html,

  -- 直近7日に配信したメッセージ
  CASE WHEN a.top_body IS NULL THEN
    '<p style="margin:0;padding:14px;border:1px solid #E0E0E0;font-size:13px;color:#666666;text-align:center;">直近7日に配信したメッセージはありません。</p>'
  ELSE
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-family:Inter,Arial,sans-serif;font-size:13px;color:#000000;">'
    || '<tr>'
    || '<th align="left"  style="background-color:#F5F5FF;padding:8px 10px;font-weight:600;white-space:nowrap;">メッセージ / 配信期間</th>'
    || '<th align="right" style="background-color:#F5F5FF;padding:8px 10px;font-weight:600;white-space:nowrap;">累計配信</th>'
    || '<th align="right" style="background-color:#F5F5FF;padding:8px 10px;font-weight:600;white-space:nowrap;">開封率</th>'
    || '<th align="right" style="background-color:#F5F5FF;padding:8px 10px;font-weight:600;white-space:nowrap;">クリック率</th>'
    || '<th align="right" style="background-color:#F5F5FF;padding:8px 10px;font-weight:600;white-space:nowrap;">失敗率</th>'
    || '</tr>' || a.top_body || '</table>'
    || IF(a.top_count > ${mail_report.max_rows}, '<p style="margin:6px 0 0 0;font-size:12px;color:#666666;">ほか ' || CAST(a.top_count - ${mail_report.max_rows} AS VARCHAR) || ' 件はダッシュボードで確認できます。</p>', '')
  END AS top_html,

  -- LINE OA Insights
  CASE WHEN NOT ${line.insights_enabled} THEN ''
  WHEN a.oa_body IS NULL THEN
    '<p style="margin:24px 0 8px 0;"><strong style="font-weight:600;white-space:nowrap;">LINE公式アカウントの配信数（LINE OA Insights）</strong></p>'
    || '<p style="margin:0;padding:14px;border:1px solid #E0E0E0;font-size:13px;color:#666666;text-align:center;">直近7日のデータはまだ取り込まれていません（通常1〜3日遅れ）。</p>'
  ELSE
    '<p style="margin:24px 0 8px 0;"><strong style="font-weight:600;white-space:nowrap;">LINE公式アカウントの配信数（LINE OA Insights）</strong></p>'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-family:Inter,Arial,sans-serif;font-size:12px;color:#000000;">'
    || '<tr>'
    || '<th align="left"  style="padding:6px 8px;border-bottom:2px solid #8753FF;color:#8753FF;">日付</th>'
    || '<th align="right" style="padding:6px 8px;border-bottom:2px solid #8753FF;color:#8753FF;">API Push/Multicast</th>'
    || '<th align="right" style="padding:6px 8px;border-bottom:2px solid #8753FF;color:#8753FF;">一斉配信</th>'
    || '<th align="right" style="padding:6px 8px;border-bottom:2px solid #8753FF;color:#8753FF;">合計</th>'
    || '</tr>' || a.oa_body || '</table>'
    || '<p style="margin:6px 0 0 0;font-size:11px;color:#666666;">アカウント全体の送信数です（Engage Studio 以外の配信も含みます）。</p>'
  END AS line_oa_html
FROM agg a, params p
