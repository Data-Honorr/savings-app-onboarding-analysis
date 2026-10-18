-- =====================================================================
-- 04_retention.sql  |  MySQL 8.0
-- Activity definition, D1/D7/D30 retention, activation metric.
-- "Active" = any app_open OR a successful transaction on that calendar day (UTC).
-- Day N retention = active exactly N calendar days after the signup date.
-- =====================================================================
USE savings_app;

-- 1. One row per user per active day
CREATE OR REPLACE VIEW v_activity AS
SELECT user_id, DATE(event_timestamp) AS active_date
FROM v_events WHERE event_type = 'app_open'
UNION
SELECT t.user_id, DATE(t.txn_timestamp)
FROM transactions t JOIN v_users u ON u.user_id = t.user_id
WHERE t.status = 'success';

-- 2. Per-user retention flags
CREATE OR REPLACE VIEW v_user_retention AS
SELECT m.user_id, m.signup_channel, m.device_os, m.state,
       DATE(m.signup_timestamp) AS signup_date,
       DATE_SUB(DATE(m.signup_timestamp), INTERVAL WEEKDAY(m.signup_timestamp) DAY) AS signup_week,
       (m.first_transfer_at IS NOT NULL) AS did_first_transfer,
       (m.first_deposit_at  IS NOT NULL) AS did_first_deposit,
       MAX(a.active_date = DATE_ADD(DATE(m.signup_timestamp), INTERVAL 1  DAY)) AS d1,
       MAX(a.active_date = DATE_ADD(DATE(m.signup_timestamp), INTERVAL 7  DAY)) AS d7,
       MAX(a.active_date = DATE_ADD(DATE(m.signup_timestamp), INTERVAL 30 DAY)) AS d30,
       -- activation: first deposit within 7 days of signup
       (m.first_deposit_at IS NOT NULL
        AND m.first_deposit_at <= DATE_ADD(m.signup_timestamp, INTERVAL 7 DAY)) AS activated_7d
FROM v_user_milestones m
LEFT JOIN v_activity a ON a.user_id = m.user_id
GROUP BY m.user_id, m.signup_channel, m.device_os, m.state, m.signup_timestamp,
         m.first_transfer_at, m.first_deposit_at;

-- A. Overall
SELECT COUNT(*) users,
       ROUND(100*AVG(d1),1) d1_pct, ROUND(100*AVG(d7),1) d7_pct, ROUND(100*AVG(d30),1) d30_pct,
       ROUND(100*AVG(activated_7d),1) activated_7d_pct
FROM v_user_retention;

-- B. By channel
SELECT signup_channel, COUNT(*) users,
       ROUND(100*AVG(d1),1) d1_pct, ROUND(100*AVG(d7),1) d7_pct, ROUND(100*AVG(d30),1) d30_pct,
       ROUND(100*AVG(activated_7d),1) activated_7d_pct
FROM v_user_retention GROUP BY signup_channel ORDER BY d30_pct DESC;

-- C. By device OS
SELECT device_os, COUNT(*) users,
       ROUND(100*AVG(d1),1) d1_pct, ROUND(100*AVG(d7),1) d7_pct, ROUND(100*AVG(d30),1) d30_pct
FROM v_user_retention GROUP BY device_os;

-- D. By first-transfer status (descriptive only, see caveat in the write-up)
SELECT did_first_transfer, COUNT(*) users,
       ROUND(100*AVG(d1),1) d1_pct, ROUND(100*AVG(d7),1) d7_pct, ROUND(100*AVG(d30),1) d30_pct
FROM v_user_retention GROUP BY did_first_transfer;

-- E. Weekly signup cohorts (feeds the retention heatmap)
SELECT signup_week, COUNT(*) cohort_size,
       ROUND(100*AVG(d1),1) d1_pct, ROUND(100*AVG(d7),1) d7_pct, ROUND(100*AVG(d30),1) d30_pct
FROM v_user_retention GROUP BY signup_week ORDER BY signup_week;

-- F. Weekday vs weekend signup (seasonality check)
SELECT CASE WHEN DAYOFWEEK(signup_date) IN (1,7) THEN 'weekend' ELSE 'weekday' END day_type,
       COUNT(*) users, COUNT(DISTINCT signup_date) days,
       ROUND(COUNT(*)/COUNT(DISTINCT signup_date)) avg_signups_per_day
FROM v_user_retention GROUP BY day_type;
