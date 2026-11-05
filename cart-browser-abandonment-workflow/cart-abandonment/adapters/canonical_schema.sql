-- Provisioning reference, NOT invoked by the workflow. Requires explicit approval.
-- Create databases separately. All business timestamps are BIGINT Unix seconds.
-- See README for required uniqueness, complete-snapshot and identity contracts.
CREATE TABLE IF NOT EXISTS ${config.sources.events} (
  time BIGINT, event_id VARCHAR, device_id VARCHAR, member_id VARCHAR,
  event_type VARCHAR, product_id VARCHAR, quantity BIGINT, item_position BIGINT,
  item_name VARCHAR, item_url VARCHAR, image_url VARCHAR, brand VARCHAR,
  price DOUBLE, original_price DOUBLE
);
CREATE TABLE IF NOT EXISTS ${config.sources.identities} (
  time BIGINT, row_id VARCHAR, device_id VARCHAR, member_id VARCHAR, updated_at BIGINT
);
CREATE TABLE IF NOT EXISTS ${config.sources.recipients} (
  time BIGINT, row_id VARCHAR, member_id VARCHAR, email VARCHAR,
  consent BOOLEAN, suppressed BOOLEAN, updated_at BIGINT
);
CREATE TABLE IF NOT EXISTS ${config.sources.orders} (
  time BIGINT, order_id VARCHAR, member_id VARCHAR, product_id VARCHAR, cancelled BOOLEAN
);
CREATE TABLE IF NOT EXISTS ${config.sources.products} (
  time BIGINT, row_id VARCHAR, product_id VARCHAR, updated_at BIGINT,
  item_name VARCHAR, item_url VARCHAR, image_url VARCHAR, brand VARCHAR,
  price DOUBLE, original_price DOUBLE, published BOOLEAN, available BOOLEAN, low_stock BOOLEAN
);
CREATE TABLE IF NOT EXISTS ${config.sources.recommendations} (
  time BIGINT, row_id VARCHAR, member_id VARCHAR, snapshot_at BIGINT, updated_at BIGINT,
  product_id VARCHAR, position BIGINT, item_name VARCHAR, item_url VARCHAR,
  image_url VARCHAR, brand VARCHAR, price DOUBLE, original_price DOUBLE, available BOOLEAN
);
CREATE TABLE IF NOT EXISTS ${config.sources.attributes} (
  time BIGINT, row_id VARCHAR, member_id VARCHAR, updated_at BIGINT, points DOUBLE, segment VARCHAR
);
CREATE TABLE IF NOT EXISTS ${config.sources.coupons} (
  time BIGINT, row_id VARCHAR, member_id VARCHAR, updated_at BIGINT,
  code VARCHAR, description VARCHAR, image_url VARCHAR, valid_from BIGINT,
  valid_until BIGINT, active BOOLEAN
);
CREATE TABLE IF NOT EXISTS ${config.sources.history} (
  member_id VARCHAR, kind VARCHAR, decision_id VARCHAR, time BIGINT, status VARCHAR, attempt_id VARCHAR
);
