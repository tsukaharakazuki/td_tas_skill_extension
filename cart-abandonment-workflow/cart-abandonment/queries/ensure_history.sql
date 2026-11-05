-- Persistent shared cart/browser reservation ledger. Never CTAS/drop this table.
CREATE TABLE IF NOT EXISTS ${config.sources.history} (
  member_id VARCHAR, kind VARCHAR, decision_id VARCHAR, time BIGINT, status VARCHAR, attempt_id VARCHAR
)
