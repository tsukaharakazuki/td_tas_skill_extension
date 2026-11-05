-- =====================================================================
-- 集計期間（送信日が直近 lookback_days 日）の行を削除し、作り直せるようにします
-- target: 削除するテーブル名（table_prefix を除いた名前）
-- =====================================================================
DELETE FROM ${output_db}.${table_prefix}${target}
WHERE time >= TD_TIME_ADD(TD_DATE_TRUNC('day', ${session_unixtime}, '${tz}'), '-${lookback_days}d', '${tz}')
