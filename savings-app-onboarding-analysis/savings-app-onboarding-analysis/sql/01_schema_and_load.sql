-- =====================================================================
-- 01_schema_and_load.sql  |  MySQL 8.0
-- Creates the database, tables and loads the four CSVs from /data.
-- Edit the file paths, and run MySQL with local_infile enabled
-- (or use Workbench: right-click table > Table Data Import Wizard).
-- =====================================================================
CREATE DATABASE IF NOT EXISTS savings_app;
USE savings_app;

CREATE TABLE users (
  user_id INT PRIMARY KEY,
  signup_timestamp DATETIME NOT NULL,
  signup_channel VARCHAR(20),
  device_os VARCHAR(10),
  state VARCHAR(30),
  age_band VARCHAR(10),
  is_test_account TINYINT,
  INDEX idx_signup (signup_timestamp)
);

CREATE TABLE events (
  event_id INT PRIMARY KEY,
  user_id INT NOT NULL,
  event_type VARCHAR(30) NOT NULL,
  event_timestamp DATETIME NOT NULL,
  device_os VARCHAR(10),
  INDEX idx_user_time (user_id, event_timestamp),
  INDEX idx_type (event_type),
  FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE experiment_assignments (
  user_id INT PRIMARY KEY,
  experiment_name VARCHAR(30),
  variant VARCHAR(10),
  assigned_at DATETIME,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE transactions (
  txn_id INT PRIMARY KEY,
  user_id INT NOT NULL,
  txn_type VARCHAR(20),
  amount_ngn DECIMAL(14,2),
  txn_timestamp DATETIME NOT NULL,
  status VARCHAR(10),
  INDEX idx_user_time (user_id, txn_timestamp),
  FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- Load order matters: users first.
LOAD DATA LOCAL INFILE 'data/Users.csv' INTO TABLE users
FIELDS TERMINATED BY ',' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/Experiment-Assignments.csv' INTO TABLE experiment_assignments
FIELDS TERMINATED BY ',' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/Events.csv' INTO TABLE events
FIELDS TERMINATED BY ',' IGNORE 1 LINES
(event_id, user_id, event_type, event_timestamp, @os)
SET device_os = NULLIF(TRIM(@os), '');

LOAD DATA LOCAL INFILE 'data/Transactions.csv' INTO TABLE transactions
FIELDS TERMINATED BY ',' IGNORE 1 LINES;

-- Sanity check: expect 50,000 / 335,329 / 24,486 / 39,344
SELECT 'users' t, COUNT(*) n FROM users
UNION ALL SELECT 'events', COUNT(*) FROM events
UNION ALL SELECT 'experiment_assignments', COUNT(*) FROM experiment_assignments
UNION ALL SELECT 'transactions', COUNT(*) FROM transactions;
