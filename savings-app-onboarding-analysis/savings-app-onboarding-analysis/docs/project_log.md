# Project Log: Onboarding Funnel, Retention & A/B Test (Mobile Savings App)

Running record of each step, the reason for it, and what it found. Feeds the README's Methodology and Results sections.

## Step 0. Synthetic data
- **What:** AI-written Python generator (seed 42) produced 4 CSVs: users, events, transactions, experiment_assignments. Patterns were planted on purpose (KYC drop-off, channel quality gap, an OS-skewed experiment) and an answer key was kept out of the analysis.
- **Why:** Real fintech data isn't public. Planted patterns give the analysis something real to find and let results be verified.

## Step 1. Load into MySQL 8.0
- **What:** Created schema with keys and indexes; loaded CSVs; checked row counts (50,000 / 335,329 / 24,486 / 39,344).
- **Why:** Row counts confirm nothing was lost in loading before any analysis starts.
- **Note:** Timestamps carried a `+00:00` suffix that MySQL's loader rejects, so it was stripped; all times are UTC.

## Step 2. Data audit and cleaning (`02_clean_views.sql`)
- **Findings:** 725 test accounts; 3,320 duplicate events; 599 users with KYC completed before KYC started; 1,088 users with KYC completed but no BVN event.
- **Decisions and why:**
  - Test accounts excluded: they are not customers.
  - Duplicates removed with `ROW_NUMBER()`: same user, event type and timestamp is one event logged twice.
  - Out-of-order users kept in funnel counts but flagged: funnel counting asks "did the user ever reach the step", so timestamp errors don't distort it. They are excluded from any time-to-convert metric.
  - BVN treated as a diagnostic, not a funnel stage: 1,088 users skip it and KYC completion is about 57% with or without it.
- **Result:** 49,275 real users in a one-row-per-user milestone view.

## Step 3. Funnel (`03_funnel.sql`)
- **Result:** Signup 100% > KYC started 77.8% > KYC completed 44.4% > first deposit 29.1% > first transfer 16.8%.
- **Findings:** KYC start-to-complete (57.0%) is the biggest loss, about 16,500 users. Android completes KYC at 53.6% vs iOS 63.1%. Channels look identical through KYC and diverge at deposit: paid social 24.3% activation, referral 38.6%.

## Step 4. Retention and activation (`04_retention.sql`)
- **Definitions:** Active = app open or successful transaction. Day N retention = active exactly N days after signup date. Activation = first deposit within 7 days.
- **Result:** D1 38.5%, D7 25.8%, D30 13.9%, 7-day activation 28.8%. Referral D30 20.8% vs paid social 10.4%. Android and iOS retain equally.
- **Caveat recorded:** first-transfer users retain far better (D30 24.9% vs 11.7%), but transfers count as activity and engaged users transfer more, so this is a marker of engagement, not proof of cause.

## Step 5. A/B test (`05_ab_test.py`)
- **Design choices and why:**
  - Primary metric is KYC completion among KYC starters, because the redesign changes that step. Intent-to-treat metrics (signup to KYC, activation, D30) reported as secondary.
  - Checked sample ratio, covariate balance, and the pre-treatment step (signup to KYC started) before trusting the result.
  - Cut by OS and standardised to a common OS mix, because the arms have different OS shares.
- **Result:** KYC completion 55.3% control vs 65.8% treatment (+10.5 pp, 95% CI +9.1 to +11.9, p < 0.001). Android +16.3 pp, iOS +3.8 pp. OS-standardised lift +11.0 pp. 7-day activation +4.8 pp. D30 retention unchanged (14.3% vs 14.1%).
- **Limitation recorded:** Android share is 61.6% in treatment vs 54.3% in control (p < 0.001), so randomisation was not balanced on OS. The OS-adjusted estimate is the one to report, and future tests should stratify by OS.

## Step 6. Visuals (`06_visuals.py`)
- **What:** Four charts built from the MySQL views: funnel, retention heatmap by weekly signup cohort, A/B uplift with 95% CIs, and channel quality.
- **Why each one:** The funnel shows where users are lost; the heatmap shows whether retention is stable across cohorts; the uplift chart shows the effect size and its uncertainty by OS; the channel chart supports the acquisition recommendation.
- **Design choices:** The KYC bar is highlighted because it is the bottleneck. The uplift chart marks the OS-adjusted estimate (+11.0 pp) next to the unadjusted one so the imbalance is visible.
- **Synthetic-data artifact to disclose:** The heatmap shows activity concentrated on D1, D7 and D30, with almost none on other days. Real products show a smoother decay curve. The README should say this comes from how the data was generated.
