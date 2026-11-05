-- Conservative idempotency: one stable decision per member/kind/source event.
-- The attempt binding prevents a new attempt from exporting an old reservation.
SELECT p.member_id, p.kind, p.decision_id, p.run_time AS time, 'reserved' AS status,
       '${attempt_id}' AS attempt_id
FROM ${config.output.database}.${config.output.prefix}_send_list p
WHERE p.run_time = ${session_unixtime}
  AND NOT EXISTS (SELECT 1 FROM ${config.sources.history} h WHERE h.decision_id = p.decision_id)
