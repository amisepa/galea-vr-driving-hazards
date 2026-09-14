/* Build the Supplementary Material for the Galea VR collision paper as a .docx.
 *
 * Like build_manuscript.js, every number is read from the analysis output
 * rather than typed by hand:
 *   Table S1  data/random_stim_sequences/qrandom_diagnostics_summary.csv
 *   Table S2  results_final/EEG_covariates/covariate_summary.csv
 *   Table S3  results_final/ML/coauthor_classification.csv
 *
 * Usage:  node build_supplementary.js
 */

const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, AlignmentType, ImageRun,
  Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle,
  Footer, PageNumber, convertInchesToTwip,
} = require('docx');

const ROOT = 'C:\\Users\\ccann\\Documents\\MATLAB\\galea';
const RES = path.join(ROOT, 'results_final');

const FONT = 'Times New Roman';
const SZ = 24;        // 12 pt
const SZ_SMALL = 20;  // 10 pt
const TW = 9360;      // usable width, US Letter with 1" margins (DXA)

/* ------------------------------------------------------------------ */
/* helpers                                                             */
/* ------------------------------------------------------------------ */

function readCSV(p) {
  if (!fs.existsSync(p)) throw new Error(`missing input: ${p}`);
  const lines = fs.readFileSync(p, 'utf8').trim().split(/\r?\n/);
  const head = lines[0].split(',').map((h) => h.trim());
  return lines.slice(1).map((l) => {
    const cells = l.split(',');
    const o = {};
    head.forEach((h, i) => {
      const v = cells[i];
      o[h] = (v === undefined || v === '' || isNaN(parseFloat(v))) ? v : parseFloat(v);
    });
    return o;
  });
}

const fx = (x, d) => (x === undefined || x === null || isNaN(x) ? '\u2014' : Number(x).toFixed(d));

function stats(arr) {
  const v = arr.filter((x) => typeof x === 'number' && !isNaN(x));
  const m = v.reduce((a, b) => a + b, 0) / v.length;
  const sd = Math.sqrt(v.reduce((a, b) => a + (b - m) ** 2, 0) / (v.length - 1));
  return { m, sd, min: Math.min(...v), max: Math.max(...v), n: v.length };
}

const P = (text, opts = {}) => new Paragraph({
  spacing: { line: 360, after: 160 },
  alignment: opts.center ? AlignmentType.CENTER : AlignmentType.LEFT,
  children: [new TextRun({ text, font: FONT, size: opts.size || SZ, bold: opts.bold, italics: opts.italic })],
});

const H1 = (text) => new Paragraph({
  spacing: { before: 320, after: 200 },
  children: [new TextRun({ text, font: FONT, size: 28, bold: true })],
});

const H2 = (text) => new Paragraph({
  spacing: { before: 280, after: 140 },
  children: [new TextRun({ text, font: FONT, size: SZ, bold: true })],
});

const CAPTION = (label, text) => new Paragraph({
  spacing: { before: 80, after: 260 },
  children: [
    new TextRun({ text: label + ' ', font: FONT, size: SZ_SMALL, bold: true }),
    new TextRun({ text, font: FONT, size: SZ_SMALL }),
  ],
});

function makeTable(header, rows, widths) {
  const total = widths.reduce((a, b) => a + b, 0);
  const colW = widths.map((w) => Math.round((w / total) * TW));
  colW[colW.length - 1] += TW - colW.reduce((a, b) => a + b, 0);

  const cell = (txt, i, opts = {}) => new TableCell({
    width: { size: colW[i], type: WidthType.DXA },
    shading: opts.head ? { type: ShadingType.CLEAR, fill: 'EDEDED', color: 'auto' } : undefined,
    margins: { top: 60, bottom: 60, left: 90, right: 90 },
    children: [new Paragraph({
      spacing: { line: 240, after: 0 },
      alignment: i === 0 ? AlignmentType.LEFT : AlignmentType.CENTER,
      keepNext: true,   // hold the table, and its caption, on one page
      children: [new TextRun({ text: String(txt), font: FONT, size: SZ_SMALL, bold: opts.head })],
    })],
  });

  return new Table({
    width: { size: TW, type: WidthType.DXA },
    columnWidths: colW,
    borders: {
      top: { style: BorderStyle.SINGLE, size: 6, color: '000000' },
      bottom: { style: BorderStyle.SINGLE, size: 6, color: '000000' },
      left: { style: BorderStyle.NONE }, right: { style: BorderStyle.NONE },
      insideHorizontal: { style: BorderStyle.SINGLE, size: 2, color: 'BFBFBF' },
      insideVertical: { style: BorderStyle.NONE },
    },
    rows: [
      new TableRow({ tableHeader: true, cantSplit: true, children: header.map((h, i) => cell(h, i, { head: true })) }),
      ...rows.map((r) => new TableRow({ cantSplit: true, children: r.map((c, i) => cell(c, i)) })),
    ],
  });
}

/* ------------------------------------------------------------------ */
/* inputs                                                              */
/* ------------------------------------------------------------------ */

const qrng = readCSV(path.join(ROOT, 'data', 'random_stim_sequences', 'qrandom_diagnostics_summary.csv'));
const cov = readCSV(path.join(RES, 'EEG_covariates', 'covariate_summary.csv'));
const coML = readCSV(path.join(RES, 'ML', 'coauthor_classification.csv'));
const CLF_ORDER = ['SVM', 'k-nearest neighbours', 'Naive Bayes', 'Random forest',
  'Decision tree', 'Neural network (MLP)'];
const coRows = (win, mod, nSub) => coML
  .filter((r) => r.Window === win && r.Modality === mod && Number(r.N) === nSub)
  .sort((a, b) => CLF_ORDER.indexOf(a.Classifier) - CLF_ORDER.indexOf(b.Classifier));
const NCARD = Number(coML.find((r) => r.Modality === 'HR').N);
const nObs14 = 2 * NCARD;
const coMean = (mod) => {
  const a = coRows('post', mod, NCARD).map((r) => r.Accuracy);
  return a.reduce((x, y) => x + y, 0) / a.length;
};
const coSame = (() => {
  const a = coRows('post', 'EEG', NCARD), b = coRows('post', 'EEG+HR', NCARD);
  const K = ['Accuracy', 'Sensitivity', 'Specificity', 'Precision', 'F1'];
  return a.filter((r, i) => b[i] && K.every((k) => r[k] === b[i][k])).length;
})();

function wilson(pPct, n) {
  const z = 1.959964, p = pPct / 100;
  const d = 1 + (z * z) / n;
  const c = (p + (z * z) / (2 * n)) / d;
  const h = (z / d) * Math.sqrt((p * (1 - p)) / n + (z * z) / (4 * n * n));
  return [Math.max(0, c - h) * 100, Math.min(1, c + h) * 100];
}

const ACF_LAGS = 10;
const maxAbsACF = qrng.map((r) => Math.max(
  ...Array.from({ length: ACF_LAGS }, (_, k) => Math.abs(r[`ACF_Lag${k + 1}`])),
));

const sProp = stats(qrng.map((r) => r.Proportion_1s));
const sEnt = stats(qrng.map((r) => r.Shannon_Entropy));
const sRuns = stats(qrng.map((r) => r.RunsTest_p));
const sACF = stats(maxAbsACF);
const nFailRuns = qrng.filter((r) => r.RunsTest_p < 0.05).length;

const covNull = cov.filter((r) => r.nClusters === 0).length;

/* ------------------------------------------------------------------ */
/* document                                                            */
/* ------------------------------------------------------------------ */

const children = [];

children.push(P('Supplementary Material', { bold: true, size: 32, center: true }));
children.push(P('Reactive and predictive processes during unpredictable driving hazards in virtual '
  + 'reality: an exploratory brain and body study with multimodal neurophysiological '
  + 'monitoring', { italic: true, size: SZ_SMALL, center: true }));
children.push(P('C\u00e9dric Cannard & Demet Ye\u015filba\u015f', { size: SZ_SMALL, center: true }));

/* ---------- S1 ---------- */
children.push(H1('S1. Quantum random number generator sequence diagnostics'));
children.push(P('Trial sequences were generated before data collection with a quantum random number '
  + `generator and validated blind, before any recording took place. All ${qrng.length} pre-generated `
  + 'sequences were tested; the table summarises the four diagnostics across them. The full '
  + 'per-sequence values are in data/random_stim_sequences/qrandom_diagnostics_summary.csv in the '
  + 'repository.'));

children.push(makeTable(
  ['Diagnostic', 'Mean', 'SD', 'Minimum', 'Maximum'],
  [
    ['Proportion of collision trials', fx(sProp.m, 3), fx(sProp.sd, 3), fx(sProp.min, 3), fx(sProp.max, 3)],
    ['Shannon entropy (bits)', fx(sEnt.m, 4), fx(sEnt.sd, 4), fx(sEnt.min, 4), fx(sEnt.max, 4)],
    ['Wald\u2013Wolfowitz runs test, p', fx(sRuns.m, 3), fx(sRuns.sd, 3), fx(sRuns.min, 3), fx(sRuns.max, 3)],
    ['Maximum |autocorrelation|, lags 1\u201310', fx(sACF.m, 3), fx(sACF.sd, 3), fx(sACF.min, 3), fx(sACF.max, 3)],
  ],
  [34, 16, 16, 17, 17],
));
children.push(CAPTION('Table S1.', `Randomisation diagnostics across the ${qrng.length} pre-generated trial `
  + 'sequences. Each sequence assigns 120 trials independently at 50% probability. Entropy is computed on the '
  + 'binary condition sequence, where 1.0 is the maximum for an equiprobable binary source. The runs test '
  + 'evaluates the null hypothesis that the sequence is independently ordered; autocorrelation is reported as '
  + `the largest absolute coefficient over lags 1 to ${ACF_LAGS}.`));

children.push(P(`${nFailRuns} of the ${qrng.length} sequences returned a runs-test p below .05 `
  + `(${fx(100 * nFailRuns / qrng.length, 0)}%), which is what independence predicts at that threshold. `
  + 'No sequence was rejected or regenerated on the basis of these diagnostics; they are reported to '
  + 'document that the source behaved as a random binary generator before any data were collected.'));

/* ---------- S2 ---------- */
children.push(H1('S2. Exploratory individual-difference models'));
children.push(P('Each individual-difference variable was entered separately as a second-level covariate in '
  + 'the hierarchical GLM, in the pre-stimulus and post-stimulus windows. Personality variables were '
  + 'available for 14 of the 16 participants and all other variables for all 16. Because each model was '
  + 'cluster-mass corrected within itself and none produced a surviving cluster, the registered false '
  + 'discovery rate step across variables had no rejections to adjust: Benjamini–Hochberg adjusted '
  + 'p-values are never smaller than the raw ones, so no family-level step could yield a rejection here. '
  + 'These results are exploratory on grounds of statistical power and are not treated as findings of the '
  + 'study.'));

children.push(makeTable(
  ['Window', 'Covariate', 'n', 'Clusters surviving correction'],
  cov.map((r) => [
    r.Window === 'post' ? 'Post-stimulus' : 'Pre-stimulus',
    String(r.Covariate).replace(/_/g, ' '),
    r.n,
    r.nClusters,
  ]),
  [22, 38, 12, 28],
));
children.push(CAPTION('Table S2a.', `The ${cov.length} time-domain individual-difference models. `
  + 'Cluster-mass permutation correction, \u03b1 = 0.05, 1000 permutations, as for the main analysis '
  + `(Section 2.6). ${covNull === cov.length ? 'No model produced a cluster surviving correction in either window.' : ''}`));

/* Moderators on the TIME-FREQUENCY clusters. The time-domain models above cannot address the
 * pre-stimulus effect, which exists only in the time-frequency domain, so registered H5 is run
 * against it here. Written by analysis/run_final_TF_covariates.m. */
const tfCov = readCSV(path.join(RES, 'EEG_covariates', 'tf_covariate_summary.csv')) || [];
if (tfCov.length) {
  const minQ = Math.min(...tfCov.map((r) => +r.q));
  children.push(P('Because the pre-stimulus effect exists only in the time-frequency domain, the '
    + 'time-domain models above cannot test the registered moderator hypothesis against it. Each '
    + 'participant\u2019s condition effect was therefore summarised as mean power within each corrected '
    + 'time-frequency cluster, and each variable was correlated with it across participants in both '
    + `windows. Benjamini\u2013Hochberg was applied across all ${tfCov.length} tests, as registered. `
    + (minQ < 0.05
      ? 'Associations surviving correction are marked.'
      : `No association survives correction (smallest q = ${fx(minQ, 2)}).`)
    + ' The cluster was selected for its group-level condition effect, which inflates the cluster mean '
    + 'but does not bias a between-participant correlation, since the selection is blind to how '
    + 'individuals rank on any questionnaire.'));
  children.push(makeTable(
    ['Window', 'Covariate', 'n', 'r', 'p', 'q'],
    tfCov.map((r) => [
      r.Window === 'post' ? 'Post-stimulus' : 'Pre-stimulus',
      String(r.Covariate).replace(/_/g, ' '),
      r.n, fx(+r.r, 2), fx(+r.p, 3), fx(+r.q, 3),
    ]),
    [22, 34, 8, 12, 12, 12],
  ));
  children.push(CAPTION('Table S2b.', `The ${tfCov.length} time-frequency individual-difference `
    + 'correlations: Pearson r between each variable and the participant\u2019s mean cluster power '
    + '(collision minus no-collision, dB). q is the Benjamini\u2013Hochberg adjusted p-value across all '
    + `${tfCov.length} tests.`));
}


/* ---------- S3 ---------- */
children.push(H1('S3. Electroencephalography, heart rate and their combination'));
children.push(P('The cardiac quality screen retained a different subset of participants from the EEG screen. '
  + `To compare the modalities fairly, this analysis is restricted to the ${NCARD} participants with usable `
  + `data in both, so that all three feature sets are evaluated on identical folds (${nObs14} observations). `
  + 'Cross-validation, classifiers and metrics are otherwise as in Section 2.8. The windows differ by '
  + 'modality: the event-related potential (ERP) features span the post-stimulus window (0 to +1200 ms), while '
  + 'the heart-rate features are mean instantaneous heart rate at eleven points spanning the full −5 to '
  + '+5 s epoch. Heart rate yields roughly one sample per beat, so a 1.2 s window would hold only one or two '
  + 'values. The feature sets are therefore matched on participants and folds but not on time window.'));

children.push(makeTable(
  ['Features', 'Classifier', 'Accuracy', '95% CI', 'Sens.', 'Spec.', 'Prec.', 'F1', 'AUC'],
  [['EEG', 'EEG'], ['HR', 'Heart rate'], ['EEG+HR', 'EEG + heart rate']].flatMap(([key, label]) =>
    coRows('post', key, NCARD).map((r) => {
      const ci = wilson(r.Accuracy, nObs14);
      return [label, r.Classifier, fx(r.Accuracy, 1), `[${fx(ci[0], 0)}, ${fx(ci[1], 0)}]`,
        fx(r.Sensitivity, 1), fx(r.Specificity, 1), fx(r.Precision, 1), fx(r.F1, 1), fx(r.AUC, 2)];
    })),
  [17, 22, 10, 14, 8, 8, 8, 7, 7],
));
children.push(CAPTION('Table S3.', 'Classification of collision versus no-collision on the matched sample of '
  + `${NCARD} participants, using the post-stimulus ERP alone (0 to +1200 ms), eleven `
  + 'heart-rate values spanning the full −5 to +5 s epoch alone, and the two concatenated. '
  + 'Leave-one-subject-out cross-validation with '
  + 'predictions pooled across folds. All values are percentages except AUC. Chance accuracy is 50%.'));

children.push(P('Heart rate alone is at chance in every classifier, with all six confidence intervals '
  + '(CIs) spanning 50% and areas under the curve (AUC) between '
  + `${fx(Math.min(...coRows('post', 'HR', NCARD).map((r) => r.AUC)), 2)} and `
  + `${fx(Math.max(...coRows('post', 'HR', NCARD).map((r) => r.AUC)), 2)}. This matches the univariate `
  + 'cardiac analysis, which found no condition difference in event-related heart rate in either window. '
  + 'Adding the cardiac features to the ERP moves mean accuracy from '
  + `${fx(coMean('EEG'), 1)}% to ${fx(coMean('EEG+HR'), 1)}%, and ${coSame} of the six classifiers return `
  + 'predictions identical to the EEG-only model on every observation. That is what dimensionality alone '
  + 'predicts, and it is why the concatenation is not interpreted on its own: eleven features cannot displace '
  + 'several thousand. The heart-rate-only column is the interpretable one, and it indicates that the '
  + 'combination had nothing to gain.'));

/* ------------------------------------------------------------------ */

/* ---------- (former S4: time-frequency normalisation comparison) ---------- */
/* PROMOTED to main-text Figure 4 (2026-09-11): the reader now sees both
 * normalisations in the paper itself, so the supplementary section was removed.
 * The figure is built by analysis/make_figures.m as
 * figure4_tf_normalisations.png. */

/* ---------- S4: H4 time-symmetry on the TF clusters ---------- */
/* Per-participant skipped-Spearman correlations and the group statistics, from
 * analysis/run_final_H4_tf_symmetry.m. Figure S1 is built by
 * analysis/make_h4_figure.py from the same CSVs. Both optional: a missing
 * table warns loudly (main text cites Supplementary Table S4) but does not
 * abort the build. */
const h4csv = path.join(RES, 'EEG_tf_causal', 'h4_tf_symmetry.csv');
const h4grpcsv = path.join(RES, 'EEG_tf_causal', 'h4_tf_symmetry_group.csv');
if (fs.existsSync(h4csv) && fs.existsSync(h4grpcsv)) {
  const h4rows = readCSV(h4csv);
  const h4g = {};
  readCSV(h4grpcsv).forEach((r) => { h4g[r.stat] = r; });
  const nPos = h4rows.filter((r) => +r.r_skipped > 0).length;
  children.push(H1('S4. Time-symmetry correlations on the time-frequency clusters'));
  children.push(P('Registered hypothesis H4 held that the magnitude of pre-stimulus differentiation '
    + 'correlates positively with the magnitude of the post-stimulus response. The registered analysis is '
    + 'peak-matched to the primary mass-univariate effects; since the pre-stimulus effect was found in the '
    + 'time-frequency domain, trial-wise indices were taken as the mean channel-averaged power within the '
    + 'pre-stimulus and post-stimulus cluster windows (Section 2.7 of the main text), correlated per '
    + 'participant with the skipped Spearman estimator of the Robust Correlation Toolbox (Pernet, Wilcox and '
    + 'Rousselet, 2012), and tested against 10,000 within-participant permutations of the pre\u2013post pairing. '
    + 'The group-level test is a one-sample t test on Fisher-transformed coefficients; the trimmed mean and '
    + 'its confidence interval are a bootstrap over participants (5,000 resamples). Because the windows come '
    + 'from these data, the analysis is exploratory.'));

  children.push(makeTable(
    ['Participant', 'r', 'p (perm)', 'Trials', 'Collision', 'No-collision'],
    h4rows.map((r) => [r.sub_label ?? r.sub, fx(+r.r_skipped, 3),
      (+r.p_perm_10k < 0.0001 ? '< .001' : fx(+r.p_perm_10k, 3)),
      r.n_trials, r.n_collision, r.n_nocollision]),
    [20, 14, 16, 13, 18, 19],
  ));
  children.push(CAPTION('Table S4.', 'Per-participant time-symmetry correlations on the time-frequency '
    + 'clusters. r is the skipped Spearman correlation between trial-wise mean power in the pre-stimulus '
    + 'cluster window and in the post-stimulus cluster window; p is the two-tailed permutation p-value '
    + '(10,000 pairing permutations). Trials are the retained artefact-free epochs entering each '
    + 'correlation.'));

  const FIG_S1 = path.join(ROOT, 'manuscript', 'figures', 'figureS1_h4_forest.png');
  if (fs.existsSync(FIG_S1)) {
    const buf2 = fs.readFileSync(FIG_S1);
    if (buf2.readUInt32BE(0) !== 0x89504e47) throw new Error('figureS1_h4_forest.png is not a PNG');
    const w2 = buf2.readUInt32BE(16);
    const h2 = buf2.readUInt32BE(20);
    const W2 = 624;
    children.push(new Paragraph({
      spacing: { before: 200, after: 80 },
      alignment: AlignmentType.CENTER,
      children: [new ImageRun({
        type: 'png',
        data: buf2,
        transformation: { width: W2, height: Math.round(W2 * h2 / w2) },
      })],
    }));
    children.push(CAPTION('Figure S1.', 'Per-participant time-symmetry correlations (skipped Spearman r '
      + 'between trial-wise pre- and post-stimulus power in the two time-frequency cluster windows), sorted '
      + 'by magnitude. The red diamond marks the group-level 20%-trimmed mean with its bootstrap 95% '
      + `confidence interval; all ${nPos} of ${h4rows.length} participants are positive.`));
  } else {
    console.warn('\n  WARNING: ' + path.relative(ROOT, FIG_S1) + ' does not exist.\n'
      + '  Run analysis/make_h4_figure.py, then rebuild this document.\n');
  }
  console.log(`  Table S4 : H4 time-symmetry, ${nPos}/${h4rows.length} positive, `
    + `t(${h4g.group_t_on_z.df}) = ${fx(+h4g.group_t_on_z.value, 2)}`);
} else {
  console.warn('\n  WARNING: ' + path.relative(ROOT, h4csv) + ' does not exist.\n'
    + '  The main text cites Supplementary Table S4. Run analysis/run_final_H4_tf_symmetry.m,\n'
    + '  then rebuild this document.\n');
}

const doc = new Document({
  creator: 'Cédric Cannard',
  lastModifiedBy: 'Cédric Cannard',
  styles: { default: { document: { run: { font: FONT, size: SZ } } } },
  sections: [{
    properties: {
      page: {
        margin: {
          top: convertInchesToTwip(1), bottom: convertInchesToTwip(1),
          left: convertInchesToTwip(1), right: convertInchesToTwip(1),
        },
      },
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [new TextRun({ children: ['S', PageNumber.CURRENT], font: FONT, size: SZ_SMALL })],
        })],
      }),
    },
    children,
  }],
});

Packer.toBuffer(doc).then((buf) => {
  const out = path.join(ROOT, 'manuscript', 'Supplementary_Material.docx');
  fs.writeFileSync(out, buf);
  console.log('Wrote ' + out);
  console.log(`  Table S1 : ${qrng.length} qRNG sequences, ${nFailRuns} with runs p < .05`);
  console.log(`  Table S2 : ${cov.length} covariate models, ${covNull} null`);
  console.log(`  Table S3 : EEG / HR / EEG+HR, N = ${NCARD}, ${coSame}/6 classifiers unchanged by fusion`);
});
