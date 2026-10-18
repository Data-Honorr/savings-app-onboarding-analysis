"""
06_visuals.py - charts for the README.
Inputs (exported from MySQL views): funnel.tsv, ret_curve.tsv, cohort_size.tsv, channel.tsv, ab.tsv
Outputs: ../images/*.png
"""
import os, numpy as np, pandas as pd, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from statsmodels.stats.proportion import confint_proportions_2indep

NAVY, BLUE, LIGHT, RED, GREY = "#0B2447", "#2E6FBA", "#A9C7EA", "#D1495B", "#8A94A6"
plt.rcParams.update({"font.family": "DejaVu Sans", "axes.spines.top": False, "axes.spines.right": False,
                     "axes.titleweight": "bold", "axes.titlesize": 13, "figure.dpi": 150})
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "images"); os.makedirs(OUT, exist_ok=True)

# ---------- 1. Funnel ----------
f = pd.read_csv("funnel.tsv", sep="\t").iloc[0]
steps = ["Signup", "KYC started", "KYC completed", "First deposit", "First transfer"]
vals = [f.s, f.k, f.c, f.d, f.t]
fig, ax = plt.subplots(figsize=(9, 4.6))
cols = [BLUE, BLUE, RED, BLUE, BLUE]
ax.barh(steps[::-1], vals[::-1], color=cols[::-1], height=0.62)
for i, (s, v) in enumerate(zip(steps, vals)):
    y = len(steps) - 1 - i
    step = "" if i == 0 else f"  ({100*v/vals[i-1]:.1f}% of previous step)"
    ax.text(v + 600, y, f"{int(v):,}  {100*v/vals[0]:.1f}%{step}", va="center", fontsize=9, color=NAVY)
ax.set_xlim(0, vals[0] * 1.62); ax.set_xticks([])
ax.set_title("Onboarding funnel: KYC completion is the biggest drop-off", loc="left")
ax.spines["bottom"].set_visible(False)
plt.tight_layout(); plt.savefig(f"{OUT}/01_funnel.png"); plt.close()

# ---------- 2. Retention heatmap (weekly cohorts x days since signup) ----------
r = pd.read_csv("ret_curve.tsv", sep="\t"); cs = pd.read_csv("cohort_size.tsv", sep="\t")
m = r.pivot(index="cohort_week", columns="n", values="active_users").fillna(0)
m = m.div(cs.set_index("cohort_week").loc[m.index, "size"], axis=0) * 100
labels = [f"{pd.to_datetime(w):%d %b}  (n={int(cs.set_index('cohort_week').loc[w,'size']):,})" for w in m.index]
fig, ax = plt.subplots(figsize=(11, 5.6))
im = ax.imshow(m.values, aspect="auto", cmap="Blues", vmin=0, vmax=45)
ax.set_yticks(range(len(m))); ax.set_yticklabels(labels, fontsize=8)
ax.set_xticks([0, 6, 13, 20, 29]); ax.set_xticklabels(["D1", "D7", "D14", "D21", "D30"])
for col, name in [(0, "D1"), (6, "D7"), (29, "D30")]:
    for i, v in enumerate(m[col + 1].values):
        ax.text(col, i, f"{v:.0f}", ha="center", va="center", fontsize=7.5, color="white" if v > 22 else NAVY)
ax.set_xlabel("Days since signup"); ax.set_ylabel("Signup week (Monday)")
ax.set_title("Retention by weekly signup cohort (% of cohort active)", loc="left")
cb = plt.colorbar(im, ax=ax, pad=0.01); cb.set_label("% active")
plt.tight_layout(); plt.savefig(f"{OUT}/02_retention_heatmap.png"); plt.close()

# ---------- 3. A/B uplift with 95% CIs ----------
d = pd.read_csv("ab.tsv", sep="\t"); ks = d[d.kyc_started == 1]
def lift(g):
    t, c = g[g.variant == "treatment"].kyc_completed, g[g.variant == "control"].kyc_completed
    lo, hi = confint_proportions_2indep(t.sum(), len(t), c.sum(), len(c), method="wald")
    return 100 * (t.mean() - c.mean()), 100 * lo, 100 * hi
rows = [("All users (unadjusted)", lift(ks)), ("Android", lift(ks[ks.device_os == "Android"])), ("iOS", lift(ks[ks.device_os == "iOS"]))]
fig, ax = plt.subplots(figsize=(9, 3.9))
for i, (lab, (est, lo, hi)) in enumerate(rows[::-1]):
    ax.errorbar(est, i, xerr=[[est - lo], [hi - est]], fmt="o", color=BLUE, ecolor=BLUE, capsize=5, markersize=8, lw=2)
    ax.text(hi + 0.7, i, f"+{est:.1f} pp  [{lo:+.1f}, {hi:+.1f}]", va="center", fontsize=9, color=NAVY)
ax.axvline(0, color=GREY, lw=1, ls="--")
ax.axvline(11.0, color=RED, lw=1.2, ls=":"); ax.text(11.0, 2.55, "OS-adjusted +11.0 pp", color=RED, fontsize=8.5, ha="center")
ax.set_yticks(range(3)); ax.set_yticklabels([r[0] for r in rows[::-1]])
ax.set_xlim(-1, 27); ax.set_ylim(-0.5, 2.8)
ax.set_xlabel("Lift in KYC completion among KYC starters (percentage points, 95% CI)")
ax.set_title("New onboarding lifts KYC completion, most strongly on Android", loc="left")
plt.tight_layout(); plt.savefig(f"{OUT}/03_ab_uplift.png"); plt.close()

# ---------- 4. Channel quality ----------
ch = pd.read_csv("channel.tsv", sep="\t").sort_values("users", ascending=False)
x = np.arange(len(ch)); w = 0.38
fig, ax = plt.subplots(figsize=(9, 4.4))
b1 = ax.bar(x - w/2, ch.activated * 100, w, color=BLUE, label="7-day activation")
b2 = ax.bar(x + w/2, ch.d30 * 100, w, color=LIGHT, label="D30 retention")
for b in list(b1) + list(b2): ax.text(b.get_x() + b.get_width()/2, b.get_height() + 0.6, f"{b.get_height():.1f}%", ha="center", fontsize=8.5, color=NAVY)
ax.set_xticks(x); ax.set_xticklabels([f"{c.replace('_',' ').title()}\n{int(u):,} signups" for c, u in zip(ch.signup_channel, ch.users)])
ax.set_ylabel("% of signups"); ax.legend(frameon=False)
ax.set_title("Paid social brings the most signups but the weakest activation and retention", loc="left", fontsize=11.5)
plt.tight_layout(); plt.savefig(f"{OUT}/04_channel_quality.png"); plt.close()
print("charts written to", os.path.abspath(OUT))
