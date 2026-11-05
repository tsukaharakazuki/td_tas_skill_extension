-- Stop before reservation/export if the frozen list contains ANY prior signal.
-- This is a serial-writer guard, not an atomic cross-project lock.
SELECT COUNT(*) AS recipient_count,
       COALESCE(SUM(CASE WHEN EXISTS (
         SELECT 1 FROM ${config.sources.history} h WHERE h.decision_id = p.decision_id
       ) THEN 1 ELSE 0 END), 0) AS existing_decision_count
FROM ${config.output.database}.${config.output.prefix}_send_list p
WHERE p.run_time = ${session_unixtime}
