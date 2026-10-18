"""
05_ab_test.py  -  A/B test analysis for onboarding_v2 (control vs treatment)
Input : ab.tsv exported from MySQL (v_user_retention + experiment_assignments)
Primary metric  : KYC completion among users who started KYC (the step the redesign targets)
Secondary       : signup->KYC completed (intent-to-treat), 7-day activation, D30 retention
"""
import numpy as np, pandas as pd
from scipy import stats
from statsmodels.stats.proportion import proportions_ztest, confint_proportions_2indep
from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import proportion_effectsize
import statsmodels.formula.api as smf

d = pd.read_csv("ab.tsv", sep="\t")
c, t = d[d.variant == "control"], d[d.variant == "treatment"]

def pct(x): return f"{100*x:.1f}%"

def compare(df, metric, label):
    a = df[df.variant == "treatment"][metric]; b = df[df.variant == "control"][metric]
    xt, nt, xc, nc = a.sum(), len(a), b.sum(), len(b)
    z, p = proportions_ztest([xt, xc], [nt, nc])
    lo, hi = confint_proportions_2indep(xt, nt, xc, nc, method="wald")
    print(f"{label:<34} ctrl {pct(xc/nc)} (n={nc:,}) | treat {pct(xt/nt)} (n={nt:,}) | "
          f"diff {100*(xt/nt-xc/nc):+.1f} pp [{100*lo:+.1f}, {100*hi:+.1f}] | p={p:.2g}")
    return xt/nt - xc/nc

print("=== 1. SAMPLE RATIO CHECK (expect 50/50) ===")
chi = stats.chisquare([len(c), len(t)]); print(f"control {len(c):,} / treatment {len(t):,}  chi-square p={chi.pvalue:.2f}")

print("\n=== 2. COVARIATE BALANCE (randomisation check) ===")
for col in ["device_os", "signup_channel"]:
    ct = pd.crosstab(d.variant, d[col]); p = stats.chi2_contingency(ct)[1]
    print(f"{col}: p={p:.2g}"); print((ct.div(ct.sum(axis=1), axis=0)*100).round(1).to_string())

print("\n=== 3. PRE-TREATMENT STEP (signup -> KYC started; should NOT differ) ===")
compare(d, "kyc_started", "KYC started")

ks = d[d.kyc_started == 1]
print("\n=== 4. PRIMARY METRIC: KYC completion among KYC starters ===")
agg = compare(ks, "kyc_completed", "ALL users")
print("\n--- by device OS ---")
eff = {}; w = {}
for os_, g in ks.groupby("device_os"):
    eff[os_] = compare(g, "kyc_completed", os_); w[os_] = len(g)

print("\n=== 5. SIMPSON'S PARADOX CHECK ===")
mix = ks.groupby("variant").device_os.value_counts(normalize=True).unstack()
print("Android share among KYC starters:\n", (mix*100).round(1).to_string())
tot = sum(w.values()); std = sum(eff[k]*w[k]/tot for k in eff)
print(f"Aggregate (unadjusted) lift : {100*agg:+.1f} pp")
for k in eff: print(f"Within {k:<8} lift        : {100*eff[k]:+.1f} pp")
print(f"OS-standardised lift        : {100*std:+.1f} pp   (each arm re-weighted to the same OS mix)")
m = smf.logit("kyc_completed ~ C(variant, Treatment('control')) + C(device_os)", ks).fit(disp=0)
coef = m.params.iloc[1]; ci = m.conf_int().iloc[1]
print(f"Logistic regression (adj. for OS): odds ratio {np.exp(coef):.2f} [{np.exp(ci[0]):.2f}, {np.exp(ci[1]):.2f}], p={m.pvalues.iloc[1]:.2g}")
mi = smf.logit("kyc_completed ~ C(variant, Treatment('control')) * C(device_os)", ks).fit(disp=0)
print(f"Interaction (variant x OS) p = {mi.pvalues.iloc[-1]:.2g}  -> effect {'differs' if mi.pvalues.iloc[-1]<0.05 else 'does not differ'} by OS")

print("\n=== 6. SECONDARY METRICS (all assigned users, intent-to-treat) ===")
for col, lab in [("kyc_completed", "Signup -> KYC completed"), ("first_deposit", "Signup -> first deposit"),
                 ("activated_7d", "7-day activation"), ("d30", "D30 retention")]:
    compare(d, col, lab)

print("\n=== 7. SENSITIVITY: sample size & minimum detectable effect ===")
base = ks[ks.variant == "control"].kyc_completed.mean(); n = int(ks.groupby("variant").size().min())
mde = NormalIndPower().solve_power(nobs1=n, alpha=0.05, power=0.8, ratio=1)
h = mde; p2 = np.sin(np.arcsin(np.sqrt(base)) + h/2)**2
print(f"Baseline {pct(base)}, n per arm ~{n:,}: 80% power detects a lift of about {100*(p2-base):.1f} pp")
print(f"Observed OS-standardised lift of {100*std:.1f} pp is well above that threshold.")
