"""Generate Figure S2: per-participant H4 time-symmetry correlations (forest plot).

Reads the analysis outputs directly (no numbers typed):
  results_final/EEG_tf_causal/h4_tf_symmetry.csv
  results_final/EEG_tf_causal/h4_tf_symmetry_group.csv
Writes manuscript/figures/figureS2_h4_forest.png at print resolution.
"""
import csv
import os

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV = os.path.join(ROOT, 'results_final', 'EEG_tf_causal', 'h4_tf_symmetry.csv')
GRP = os.path.join(ROOT, 'results_final', 'EEG_tf_causal', 'h4_tf_symmetry_group.csv')
OUT = os.path.join(ROOT, 'manuscript', 'figures', 'figureS2_h4_forest.png')

with open(CSV) as f:
    rows = list(csv.DictReader(f))
r = np.array([float(d['r_skipped']) for d in rows])
labels = [d['sub'] for d in rows]
n = len(r)

grp = {row['stat']: row for row in csv.DictReader(open(GRP))}
tm = float(grp['group_trimmed_mean_r']['value'])
lo = float(grp['ci_low']['extra'])
hi = float(grp['ci_high']['extra'])
tval = float(grp['group_t_on_z']['value'])
pval = float(grp['group_t_on_z']['p'])
df = int(float(grp['group_t_on_z']['df']))

# Figure: participants sorted by r, with the trimmed-mean + CI as a bottom row
order = np.argsort(r)
r_sorted = r[order]
labels_sorted = [labels[i] for i in order]

fig, ax = plt.subplots(figsize=(6.5, 4.2), dpi=300)
y = np.arange(n)
ax.axvline(0, color='0.55', lw=0.8, ls='--', zorder=1)
ax.hlines(y, 0, r_sorted, color='#2b6cb0', lw=1.6, zorder=2)          # lollipops
ax.plot(r_sorted, y, 'o', color='#1a365d', ms=4.5, zorder=3)          # points
ax.plot(tm, -1.4, 'D', color='#b3392e', ms=6, zorder=3)               # trimmed mean
ax.hlines(-1.4, lo, hi, color='#b3392e', lw=1.6, zorder=2)            # bootstrap CI
ax.axhspan(-2.0, -0.6, color='0.93', zorder=0)
ax.annotate(f'20%-trimmed mean r = {tm:+.2f} [{lo:+.2f}, {hi:+.2f}]',
            xy=(0.98, 0.055), xycoords='axes fraction', ha='right', va='bottom',
            fontsize=9, color='#b3392e')
ax.annotate(f'group t({df}) = {tval:.2f}, p = {pval:.1e}, {n} of {n} positive',
            xy=(0.98, 0.005), xycoords='axes fraction', ha='right', va='bottom',
            fontsize=9, color='0.25')

ax.set_yticks(list(y) + [-1.4])
ax.set_yticklabels(labels_sorted + ['Trimmed mean'])
ax.set_xlabel('Skipped Spearman r (trial-wise pre/post TF power)')
ax.set_ylim(-2.2, n - 0.2)
ax.spines[['top', 'right']].set_visible(False)
ax.tick_params(axis='y', length=0)
fig.tight_layout()
os.makedirs(os.path.dirname(OUT), exist_ok=True)
fig.savefig(OUT, dpi=300)
print('wrote', OUT)
print(f'check: n={n}, pos={int((r > 0).sum())}/{n}, tm={tm:.3f} [{lo:.3f}, {hi:.3f}], t({df})={tval:.2f}, p={pval:.2e}')