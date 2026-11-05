SELECT COUNT(*) AS recipient_count, COUNT(DISTINCT email) AS unique_email_count,
       CAST(TO_UNIXTIME(CURRENT_TIMESTAMP) AS BIGINT) - ${session_unixtime} AS execution_lag_seconds
FROM ${config.output.database}.${config.output.prefix}_send_list
WHERE run_time = ${session_unixtime}
