#!/usr/bin/env bash
# Exports the analysis datasets from the MySQL views into ./exports for the Python scripts.
# Usage (from repo root):  bash python/00_export_from_mysql.sh <mysql_user>
# Then:                    cd exports && python ../python/05_ab_test.py && python ../python/06_visuals.py
set -e
U=${1:-root}; mkdir -p exports; cd exports
q() { mysql -u"$U" -p savings_app -B -e "$1" > "$2"; }

q "SELECT r.user_id, e.variant, r.device_os, r.signup_channel, r.signup_date,
          (m.kyc_started_at IS NOT NULL) kyc_started, (m.kyc_completed_at IS NOT NULL) kyc_completed,
          r.did_first_deposit first_deposit, r.activated_7d, r.d1, r.d7, r.d30
   FROM v_user_retention r
   JOIN experiment_assignments e ON e.user_id = r.user_id
   JOIN v_user_milestones m ON m.user_id = r.user_id" ab.tsv

q "SELECT DATE_SUB(DATE(u.signup_timestamp), INTERVAL WEEKDAY(u.signup_timestamp) DAY) cohort_week,
          DATEDIFF(a.active_date, DATE(u.signup_timestamp)) n, COUNT(DISTINCT a.user_id) active_users
   FROM v_activity a JOIN v_users u ON u.user_id = a.user_id
   WHERE DATEDIFF(a.active_date, DATE(u.signup_timestamp)) BETWEEN 1 AND 30
   GROUP BY cohort_week, n" ret_curve.tsv

q "SELECT DATE_SUB(DATE(signup_timestamp), INTERVAL WEEKDAY(signup_timestamp) DAY) cohort_week, COUNT(*) size
   FROM v_users GROUP BY cohort_week" cohort_size.tsv

q "SELECT signup_channel, COUNT(*) users, AVG(activated_7d) activated, AVG(d30) d30
   FROM v_user_retention GROUP BY signup_channel" channel.tsv

q "SELECT COUNT(*) s, COUNT(kyc_started_at) k, COUNT(kyc_completed_at) c,
          COUNT(first_deposit_at) d, COUNT(first_transfer_at) t FROM v_user_milestones" funnel.tsv
echo "Exports written to ./exports"
