-- =====================================================================
-- 03_funnel.sql  |  MySQL 8.0
-- Onboarding funnel: overall, by channel, by device OS, by signup week.
-- Counting is user-level ("ever reached the step"), so timestamp
-- anomalies do not distort it.
-- =====================================================================
USE savings_app;

-- A. Overall funnel with step and cumulative conversion
WITH steps AS (
    SELECT 1 AS step_no, 'signup_completed' AS step, COUNT(*) AS users FROM v_user_milestones
    UNION ALL SELECT 2, 'kyc_started',   COUNT(kyc_started_at)   FROM v_user_milestones
    UNION ALL SELECT 3, 'kyc_completed', COUNT(kyc_completed_at) FROM v_user_milestones
    UNION ALL SELECT 4, 'first_deposit', COUNT(first_deposit_at) FROM v_user_milestones
    UNION ALL SELECT 5, 'first_transfer',COUNT(first_transfer_at)FROM v_user_milestones
)
SELECT step_no, step, users,
       ROUND(100 * users / LAG(users) OVER (ORDER BY step_no), 1)          AS step_conv_pct,
       ROUND(100 * users / FIRST_VALUE(users) OVER (ORDER BY step_no), 1)  AS cumulative_conv_pct
FROM steps ORDER BY step_no;

-- B. Funnel by acquisition channel
SELECT signup_channel,
       COUNT(*)                                                      AS signups,
       ROUND(100 * COUNT(kyc_started_at)   / COUNT(*), 1)            AS signup_to_kyc_start,
       ROUND(100 * COUNT(kyc_completed_at) / COUNT(kyc_started_at), 1) AS kyc_start_to_complete,
       ROUND(100 * COUNT(first_deposit_at) / COUNT(kyc_completed_at), 1) AS kyc_to_deposit,
       ROUND(100 * COUNT(first_transfer_at)/ COUNT(first_deposit_at), 1) AS deposit_to_transfer,
       ROUND(100 * COUNT(first_deposit_at) / COUNT(*), 1)            AS activation_pct
FROM v_user_milestones
GROUP BY signup_channel
ORDER BY signups DESC;

-- C. Funnel by device OS
SELECT device_os,
       COUNT(*)                                                      AS signups,
       ROUND(100 * COUNT(kyc_started_at)   / COUNT(*), 1)            AS signup_to_kyc_start,
       ROUND(100 * COUNT(kyc_completed_at) / COUNT(kyc_started_at), 1) AS kyc_start_to_complete,
       ROUND(100 * COUNT(first_deposit_at) / COUNT(kyc_completed_at), 1) AS kyc_to_deposit,
       ROUND(100 * COUNT(first_transfer_at)/ COUNT(first_deposit_at), 1) AS deposit_to_transfer,
       ROUND(100 * COUNT(first_deposit_at) / COUNT(*), 1)            AS activation_pct
FROM v_user_milestones
GROUP BY device_os;

-- D. Funnel by signup week (week starting Monday)
SELECT DATE_SUB(DATE(signup_timestamp), INTERVAL WEEKDAY(signup_timestamp) DAY) AS signup_week,
       COUNT(*)                                                      AS signups,
       ROUND(100 * COUNT(kyc_completed_at) / COUNT(kyc_started_at), 1) AS kyc_start_to_complete,
       ROUND(100 * COUNT(first_deposit_at) / COUNT(*), 1)            AS activation_pct
FROM v_user_milestones
GROUP BY signup_week
ORDER BY signup_week;

-- E. Where does the BVN step sit? (diagnostic, not a funnel stage)
SELECT CASE WHEN bvn_submitted_at IS NULL THEN 'no_bvn_event' ELSE 'bvn_submitted' END AS bvn_status,
       COUNT(*) AS kyc_started_users,
       ROUND(100 * COUNT(kyc_completed_at) / COUNT(*), 1) AS kyc_completion_pct
FROM v_user_milestones
WHERE kyc_started_at IS NOT NULL
GROUP BY bvn_status;
