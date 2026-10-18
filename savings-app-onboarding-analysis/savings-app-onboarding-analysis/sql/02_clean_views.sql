-- =====================================================================
-- 02_clean_views.sql  |  MySQL 8.0
-- Clean layer: exclude test accounts, de-duplicate events, build a
-- one-row-per-user milestone table used by every later analysis.
-- =====================================================================
USE savings_app;

-- 1. Real users only (test accounts excluded)
CREATE OR REPLACE VIEW v_users AS
SELECT user_id, signup_timestamp, signup_channel, device_os, state, age_band
FROM users
WHERE is_test_account = 0;

-- 2. De-duplicated events for real users.
--    Duplicates = same user, event type and timestamp with a different event_id.
--    Keep the lowest event_id of each duplicate group.
CREATE OR REPLACE VIEW v_events AS
SELECT event_id, user_id, event_type, event_timestamp, device_os
FROM (
    SELECT e.*,
           ROW_NUMBER() OVER (PARTITION BY e.user_id, e.event_type, e.event_timestamp
                              ORDER BY e.event_id) AS rn
    FROM events e
    JOIN v_users u ON u.user_id = e.user_id
) ranked
WHERE rn = 1;

-- 3. One row per user: first timestamp of each funnel milestone.
CREATE OR REPLACE VIEW v_user_milestones AS
SELECT
    u.user_id, u.signup_timestamp, u.signup_channel, u.device_os, u.state, u.age_band,
    MIN(CASE WHEN e.event_type = 'kyc_started'          THEN e.event_timestamp END) AS kyc_started_at,
    MIN(CASE WHEN e.event_type = 'bvn_submitted'        THEN e.event_timestamp END) AS bvn_submitted_at,
    MIN(CASE WHEN e.event_type = 'kyc_completed'        THEN e.event_timestamp END) AS kyc_completed_at,
    MIN(CASE WHEN e.event_type = 'first_deposit'        THEN e.event_timestamp END) AS first_deposit_at,
    MIN(CASE WHEN e.event_type = 'first_transfer'       THEN e.event_timestamp END) AS first_transfer_at,
    MIN(CASE WHEN e.event_type = 'savings_goal_created' THEN e.event_timestamp END) AS savings_goal_at
FROM v_users u
LEFT JOIN v_events e ON e.user_id = u.user_id
GROUP BY u.user_id, u.signup_timestamp, u.signup_channel, u.device_os, u.state, u.age_band;

-- 4. Data-quality flag: users whose KYC timestamps are logically out of order.
--    They stay in the funnel (reach-based counting is unaffected) but are
--    excluded from any time-to-convert metric.
CREATE OR REPLACE VIEW v_user_flags AS
SELECT user_id,
       (kyc_completed_at < kyc_started_at) AS kyc_out_of_order
FROM v_user_milestones;
