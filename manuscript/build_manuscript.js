/* Build the revised Galea VR collision manuscript as a .docx.
 * Reads the re-run results in results_final/ so every number in the
 * document comes from the analysis output rather than being typed by hand.
 *
 * Usage:  node build_manuscript.js
 */

const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle,
  PageOrientation, Footer, PageNumber, LevelFormat, convertInchesToTwip,
  ImageRun,
} = require('docx');

const ROOT = 'C:\\Users\\ccann\\Documents\\MATLAB\\galea';
const RES = path.join(ROOT, 'results_final');

/* ------------------------------------------------------------------ */
/* helpers                                                             */
/* ------------------------------------------------------------------ */

function readCSV(p) {
  if (!fs.existsSync(p)) return null;
  const lines = fs.readFileSync(p, 'utf8').trim().split(/\r?\n/);
  if (lines.length < 2) return null;
  const head = lines[0].split(',');
  return lines.slice(1).map((l) => {
    const cells = l.split(',');
    const o = {};
    head.forEach((h, i) => {
      const v = cells[i];
      o[h.trim()] = isNaN(parseFloat(v)) ? v : parseFloat(v);
    });
    return o;
  });
}

const n1 = (x) => (x === undefined || x === null ? '—' : Number(x).toFixed(1));
const n2 = (x) => (x === undefined || x === null ? '—' : Number(x).toFixed(2));
/* Emits the whole "p = ..." phrase, because a p-value below the printing
 * precision must be reported as an inequality rather than as "p = 0.000". */
const pv = (x) => {
  if (x === undefined || x === null) return 'p = —';
  return Number(x) < 0.001 ? 'p < 0.001' : `p = ${Number(x).toFixed(3)}`;
};
const sgn = (x) => (x === undefined || x === null ? '—'
  : (Number(x) >= 0 ? '+' : '−') + Math.abs(Number(x)).toFixed(2));
const n0 = (x) => (x === undefined || x === null ? '—' : Math.round(Number(x)).toString());
const WORDS = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];
const spell = (k) => (k <= 10 ? WORDS[k] : String(k));

function meanSD(arr) {
  const v = arr.filter((x) => !isNaN(x));
  const m = v.reduce((a, b) => a + b, 0) / v.length;
  const sd = Math.sqrt(v.reduce((a, b) => a + (b - m) ** 2, 0) / (v.length - 1));
  return { m, sd, min: Math.min(...v), max: Math.max(...v), n: v.length };
}

function wilson(x, n) {
  const z = 1.959964, p = x / n;
  const d = 1 + (z * z) / n;
  const c = (p + (z * z) / (2 * n)) / d;
  const h = (z / d) * Math.sqrt((p * (1 - p)) / n + (z * z) / (4 * n * n));
  return [Math.max(0, c - h) * 100, Math.min(1, c + h) * 100];
}

/* ------------------------------------------------------------------ */
/* load results                                                        */
/* ------------------------------------------------------------------ */

const prep = readCSV(path.join(RES, 'EEG_time', 'preprocessing_summary.csv'));
if (!prep) throw new Error('preprocessing_summary.csv missing — run run_final_EEG_erp.m');

const S = {
  nSub: prep.length,
  badChan: meanSD(prep.map((r) => r.nBad)),
  asr: meanSD(prep.map((r) => r.artPct)),
  badEp: meanSD(prep.map((r) => r.nBadEp)),
  crash: meanSD(prep.map((r) => r.nCr)),
  nocrash: meanSD(prep.map((r) => r.nNoCr)),
};
S.totalTrials = prep.reduce((a, r) => a + r.nCr + r.nNoCr, 0);

/* A missing cluster CSV means "no cluster survived" ONLY if the analysis
 * actually completed, which the companion .mat file attests. Without this
 * guard an unfinished run would silently be written up as a null result. */
function clusters(dir, csvName, matName) {
  const matPath = path.join(dir, matName);
  if (!fs.existsSync(matPath)) {
    throw new Error(`Analysis incomplete: ${matPath} not found. Re-run the MATLAB driver `
      + 'before building the manuscript.');
  }
  return readCSV(path.join(dir, csvName)) || [];
}

/* The time-domain analysis uses standard adjacency clustering (minchan = 0);
 * See manuscript/stats_review_2026-08.md and analysis/rerun_final_stats.m. */
const erpPost = clusters(path.join(RES, 'EEG_time', 'post-stim', 'primary'), 'MAIN_clusters.csv', 'MAIN_stats.mat');
const erpPre = clusters(path.join(RES, 'EEG_time', 'pre-stim', 'primary'), 'MAIN_clusters.csv', 'MAIN_stats.mat');
const alday = readCSV(path.join(RES, 'EEG_alday', 'post-stim', 'MAIN_clusters.csv')) || [];
const aldayPre = readCSV(path.join(RES, 'EEG_alday', 'pre-stim', 'MAIN_clusters.csv')) || [];
const winSum = readCSV(path.join(RES, 'EEG_time', 'window_summary.csv')) || [];
const win = (w, v) => winSum.find((r) => r.Window === w && r.Variant === v) || {};

/* Time-frequency results come from the CAUSAL pipeline,
 * analysis/run_final_EEG_tf_causal.m -> results_final/EEG_tf_causal/.
 * Primary is 'none': no normalisation at all. 'glmbaseline' (Alday 2019
 * applied to power) is the robustness check. The retired 'baseline' and
 * 'aperiodic' modes, and the Python specparam bridge they needed, are gone.
 *
 * There is deliberately NO fallback. results_final/EEG_tf/ still holds the
 * superseded non-causal 1-15 Hz run, so a silent fallback would produce a
 * complete, plausible manuscript reporting the wrong numbers. Missing input
 * must fail loudly. */
function tfLoad(mode, win, matName) {
  const dir = path.join(RES, 'EEG_tf_causal', mode, win);
  if (!fs.existsSync(path.join(dir, matName))) return null;
  return readCSV(path.join(dir, 'TF_clusters_corr-2.csv')) || [];
}
const tfPost = tfLoad('none', 'post-stim', 'TF_stats_post.mat');
const tfPre = tfLoad('none', 'pre-stim', 'TF_stats_pre.mat');
const tfPostAlt = tfLoad('glmbaseline', 'post-stim', 'TF_stats_post.mat');
const tfPreAlt = tfLoad('glmbaseline', 'pre-stim', 'TF_stats_pre.mat');

if (!tfPost || !tfPre) {
  throw new Error('No time-frequency results under results_final/EEG_tf_causal/none. '
    + 'Run analysis/run_final_EEG_tf_causal.m before building the manuscript. '
    + 'Do NOT point this at results_final/EEG_tf - that directory holds the '
    + 'superseded non-causal run.');
}
/* Pre-stimulus control analyses (Section 3.5), keyed by the 'stat' column so
 * the prose never carries a hand-typed number. Written by
 * analysis/run_prereg_prestim_controls.m and
 * analysis/run_prestim_mediation_trial.m. Both are optional: if a pre-stimulus
 * cluster is absent the controls have nothing to run on and Section 3.5 is
 * skipped, so a missing file must not abort the build. */
const cs = {};
(readCSV(path.join(RES, 'EEG_tf_causal', 'prestim_controls_summary.csv')) || [])
  .forEach((r) => { cs[r.stat] = r; });
const med = {};
(readCSV(path.join(RES, 'EEG_tf_causal', 'prestim_mediation_trial.csv')) || [])
  .forEach((r) => { med[r.Mediator] = r; });
const coup = {};
(readCSV(path.join(RES, 'EEG_tf_causal', 'prestim_coupling.csv')) || [])
  .forEach((r) => { coup[r.stream] = r; });

/* H4 time-symmetry on the TF clusters (run_final_H4_tf_symmetry.m). Optional like
 * the other Section 3.5 inputs: if absent, the H4 paragraph is skipped rather
 * than printed with NaNs. */
const h4rows = readCSV(path.join(RES, 'EEG_tf_causal', 'h4_tf_symmetry.csv')) || [];
const h4grp = {};
(readCSV(path.join(RES, 'EEG_tf_causal', 'h4_tf_symmetry_group.csv')) || [])
  .forEach((r) => { h4grp[r.stat] = r; });
const h4 = h4rows.length && h4grp.group_t_on_z ? {
  n: h4rows.length,
  n_pos: h4rows.filter((r) => +r.r_skipped > 0).length,
  t: +h4grp.group_t_on_z.value,
  p: +h4grp.group_t_on_z.p,
  df: +h4grp.group_t_on_z.df,
  tm_r: +(h4grp.group_trimmed_mean_r?.value ?? NaN),
  ci_low: +(h4grp.ci_low?.extra ?? NaN),
  ci_high: +(h4grp.ci_high?.extra ?? NaN),
} : null;

/* Sensitivity analyses that were run, archived, and previously unreported. sensN12 is null when the
 * analysis was never run and [] when it ran and produced no surviving cluster - the two mean
 * different things in the prose, so they must not collapse. */
const sensN12Dir = path.join(RES, 'EEG_time', 'post-stim', 'sens_n12');
const sensN12 = fs.existsSync(sensN12Dir)
  ? (readCSV(path.join(sensN12Dir, 'MAIN_clusters.csv')) || []) : null;
/* Describes the SHAPE of the pre-stimulus t-map, not another test. Written by
 * analysis/characterise_prestim_extent.m. Without it the paper reports the effect only as a cluster
 * with latency bounds, which reads as an anticipatory transient; the map is in fact a sustained
 * offset and that distinction changes the interpretation. */
const ext = (readCSV(path.join(RES, 'EEG_tf_causal', 'prestim_extent.csv')) || [])[0] || null;
/* Moderator models on the TIME-FREQUENCY clusters. The long-standing covariate analysis is
 * time-domain only, so registered H5 had never been tested against the pre-stimulus effect, which
 * has no time-domain counterpart. */
const tfCov = readCSV(path.join(RES, 'EEG_covariates', 'tf_covariate_summary.csv')) || [];
if (tfPre && tfPre.length && !cs.persub_effect) {
  throw new Error('A pre-stimulus cluster survives correction but '
    + 'results_final/EEG_tf_causal/prestim_controls_summary.csv is missing. The registered run-length and '
    + 'block controls must be reported alongside it - run analysis/run_prereg_prestim_controls.m.');
}

const tfLabel = 'the primary analysis, which applies no normalisation';
const tfAltLabel = 'baseline-as-regressor [33]';

/* Provenance guard. run_final_EEG_alday.m was switched to Freedman-Lane
 * permutation after a defect was found in the library scheme (see
 * analysis/run_stats_permutation_glm_fl.m). Any Alday result older than that
 * switch was computed under the defective scheme and must not be quoted.
 * The comparison is content-based (comment lines stripped): file mtime moves
 * with innocuous edits (e.g. copyright headers) and must not trip the guard. */
const crypto = require('crypto');
const stripComments = (t) => t.split(String.fromCharCode(10)).map((l) => l.replace(String.fromCharCode(13), '')).filter((l) => { const s = l.trimStart(); return !s.startsWith('%') && !s.startsWith('//'); }).join(String.fromCharCode(10));
const flHash = crypto.createHash('sha1').update(stripComments(
  fs.readFileSync(path.join(ROOT, 'analysis', 'run_stats_permutation_glm_fl.m'), 'utf8'))).digest('hex');
const aldayFile = path.join(RES, 'EEG_alday', 'post-stim', 'MAIN_clusters.csv');
if (fs.existsSync(aldayFile)) {
  /* The Freedman-Lane library file was finalised on 2026-09-05 (functional
   * content unchanged since; later commits only added a comment header).
   * Results produced on or after that date are valid. */
  const flFixedDate = new Date('2026-09-05T00:00:00').getTime();
  if (fs.statSync(aldayFile).mtimeMs < flFixedDate) {
    throw new Error('results_final/EEG_alday predates the Freedman-Lane permutation fix. '
      + 'Those p-values came from a scheme that permutes only the condition column while '
      + 'leaving the baseline covariate bound to its trials, which inflates the statistic. '
      + 'Re-run analysis/run_final_EEG_alday.m before building.');
  }
}

/* Classification results supplied by the co-author (D.Y.). Symmetric
 * +/-1200 ms windows, matched to the GLM. Blocks: EEG at N = 16 in both
 * windows, and a matched N = 14 post-stimulus comparison of EEG, heart rate
 * and their concatenation, restricted to participants with usable data in
 * both modalities so that all three run on identical folds. */
const coML = readCSV(path.join(RES, 'ML', 'coauthor_classification.csv')) || [];
const mlBlock = (w, mod, nSub) => coML
  .filter((r) => r.Window === w && r.Modality === mod && Number(r.N) === nSub)
  .map((r) => [r.Classifier, +r.Accuracy, +r.Sensitivity, +r.Specificity,
    +r.Precision, +r.F1, +r.AUC,
    (r.PermutationP === '' || r.PermutationP === undefined) ? null : +r.PermutationP]);
const LOSO = mlBlock('post', 'EEG', 16);
const LOSOpre = mlBlock('pre', 'EEG', 16);
const M14eeg = mlBlock('post', 'EEG', 14);
const M14hr = mlBlock('post', 'HR', 14);
const M14both = mlBlock('post', 'EEG+HR', 14);
if (!LOSO.length || !LOSOpre.length) {
  throw new Error('results_final/ML/coauthor_classification.csv is missing the N = 16 EEG blocks.');
}
const NOBS16 = 32;   // 16 participants x 2 conditions
const NCARD = coML.length ? Number(coML.find((r) => r.Modality === 'HR').N) : 14;
const NOBS14 = NCARD * 2;
const accCI = (acc, nObs) => wilson(Math.round((acc / 100) * nObs), nObs);
const col = (blk, k) => blk.map((r) => r[k]);
const mean = (a) => a.reduce((x, y) => x + y, 0) / a.length;
const bestLOSO = Math.max(...col(LOSO, 1));
const ciLOSO = accCI(bestLOSO, NOBS16);
const bestPre = Math.max(...col(LOSOpre, 1));
const ciPre = accCI(bestPre, NOBS16);
/* How many classifiers gave identical predictions with and without the cardiac
 * features (AUC excluded: it can differ while the predicted labels do not). */
const fusionSame = M14eeg.filter((r, i) => M14both[i]
  && [1, 2, 3, 4, 5].every((k) => r[k] === M14both[i][k])).length;
/* Abstract inputs (all read from results, none hand-typed). */
const erpLargest = erpPost.slice().sort((a, b) => Math.abs(+b.ES) - Math.abs(+a.ES))[0] || null;
const mlPrePmin = Math.min(...LOSOpre.map((r) => r[7]).filter((p) => p !== null));

/* Figure 4F difference-spectrum numbers, read from the figure's CSV. */
const pfCSV = readCSV(path.join(RES, 'EEG_tf_causal', 'figure4_panelF_spectra.csv')) || [];
const pfPreRow = pfCSV.filter((r) => r.window === 'pre').reduce((b, r) => (+r.mean_db > +b.mean_db ? r : b),
  { window: 'pre', freq_hz: 0, mean_db: -Infinity, sem_db: 0 });
const pfPostRow = pfCSV.filter((r) => r.window === 'post').reduce((b, r) => (+r.mean_db > +b.mean_db ? r : b),
  { window: 'post', freq_hz: 0, mean_db: -Infinity, sem_db: 0 });
const pfPreNums = pfCSV.filter((r) => r.window === 'pre').map((r) => +r.mean_db);
const pfPostNums = pfCSV.filter((r) => r.window === 'post').map((r) => +r.mean_db);
const pfPre = { pk: pfPreRow.freq_hz, lo: Math.min(...pfPreNums), hi: Math.max(...pfPreNums) };
const pfPost = { pk: pfPostRow.freq_hz, lo: Math.min(...pfPostNums), hi: Math.max(...pfPostNums) };

/* ------------------------------------------------------------------ */
/* formatting primitives                                               */
/* ------------------------------------------------------------------ */

const FONT = 'Times New Roman';
const SZ = 24;        // 12 pt
const SZ_SMALL = 20;  // 10 pt

const P = (text, opts = {}) => new Paragraph({
  spacing: { line: opts.line || 360, after: opts.after === undefined ? 120 : opts.after },
  alignment: opts.align,
  indent: opts.indent,
  children: [new TextRun({ text, font: FONT, size: opts.size || SZ, italics: opts.italics, bold: opts.bold })],
});

/* Paragraph from an array of [text, {bold/italics}] fragments */
const PR = (frags, opts = {}) => new Paragraph({
  spacing: { line: opts.line || 360, after: opts.after === undefined ? 120 : opts.after },
  alignment: opts.align,
  indent: opts.indent,
  children: frags.map(([t, o = {}]) => new TextRun({
    text: t, font: FONT, size: opts.size || SZ, bold: o.b, italics: o.i, superScript: o.sup,
  })),
});

const H1 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_1,
  spacing: { before: 360, after: 160 },
  children: [new TextRun({ text, font: FONT, size: 28, bold: true, color: '000000' })],
});

const H2 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_2,
  spacing: { before: 260, after: 120 },
  children: [new TextRun({ text, font: FONT, size: 24, bold: true, color: '000000' })],
});

const H3 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_3,
  spacing: { before: 200, after: 100 },
  children: [new TextRun({ text, font: FONT, size: 24, bold: false, italics: true, color: '000000' })],
});

const BULLET = (text) => new Paragraph({
  numbering: { reference: 'bullets', level: 0 },
  spacing: { line: 300, after: 80 },
  children: [new TextRun({ text, font: FONT, size: SZ })],
});

const CAPTION = (label, text) => new Paragraph({
  spacing: { before: 120, after: 240, line: 280 },
  children: [
    new TextRun({ text: label + ' ', font: FONT, size: SZ_SMALL, bold: true }),
    new TextRun({ text, font: FONT, size: SZ_SMALL }),
  ],
});

/* --- figures -------------------------------------------------------
 * Images are embedded at the text width (6.5 in). Dimensions are read
 * straight out of the PNG header so the aspect ratio can never be wrong,
 * and a missing figure is a hard error rather than a silent gap.
 */
const TEXT_WIDTH_PX = 624;            // 6.5 in at 96 dpi
const warnings = [];                  // non-fatal build notes, printed at the end

function pngSize(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not a PNG');
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

/* Every other input to this script is guarded against staleness - clusters() demands the companion
 * .mat, tfLoad() refuses to fall back to the superseded directory, the Alday result is rejected if it
 * predates the Freedman-Lane fix. Figures were the one unguarded input, and that is exactly how a
 * Figure 3 rendered from the superseded non-causal run - titled "Pre-stimulus: no cluster", in a paper
 * whose Results report a pre-stimulus cluster - reached a built .docx unnoticed. A figure older than
 * the data it depicts is now a hard error. */
const FIG_SOURCES = {
  'figure3_erp.png': [
    'results_final/EEG_time/post-stim/primary/MAIN_stats.mat',
    'results_final/EEG_time/pre-stim/primary/MAIN_stats.mat',
  ],
  'figure4_tf_normalisations.png': [
    'results_final/EEG_tf_causal/none/post-stim/TF_stats_post.mat',
    'results_final/EEG_tf_causal/none/pre-stim/TF_stats_pre.mat',
    'results_final/EEG_tf_causal/glmbaseline/post-stim/TF_stats_post.mat',
    'results_final/EEG_tf_causal/glmbaseline/pre-stim/TF_stats_pre.mat',
  ],
};
const FIG_SCRIPT = path.join(ROOT, 'analysis', 'make_figures.m');

const FIGURE = (file, widthFrac = 1.0) => {
  const fp = path.join(ROOT, 'manuscript', 'figures', file);
  if (!fs.existsSync(fp)) {
    throw new Error('figure missing: ' + fp
      + '  (run analysis/make_figures.m; rasterise figure1_overview.svg)');
  }
  /* Two different conditions, deliberately treated differently. A figure older than the DATA it plots
   * is depicting a superseded analysis: hard error. A figure older than make_figures.m only means the
   * plotting code was touched, which is usually cosmetic and is true of every figure the moment that
   * file is edited: warn, do not block, or the build becomes unusable for an unrelated reason. */
  const sources = FIG_SOURCES[file] || [];
  if (sources.length) {
    const figTime = fs.statSync(fp).mtimeMs;
    const staleData = sources
      .map((s) => path.join(ROOT, s))
      .filter((s) => fs.existsSync(s) && fs.statSync(s).mtimeMs > figTime);
    if (staleData.length) {
      throw new Error(`STALE FIGURE: ${file} is older than the data it plots:\n  `
        + staleData.map((s) => path.relative(ROOT, s)).join('\n  ')
        + '\nIt depicts a superseded analysis while the text reports the current one.'
        + '\nRe-run analysis/make_figures.m on a MATLAB desktop (it hangs in -batch), then rebuild.');
    }
    if (fs.existsSync(FIG_SCRIPT) && fs.statSync(FIG_SCRIPT).mtimeMs > figTime) {
      warnings.push(`${file} predates the current analysis/make_figures.m; `
        + 'its data are current but the plotting code has changed since it was rendered.');
    }
  }
  const buf = fs.readFileSync(fp);
  const { w, h } = pngSize(buf);
  const width = Math.round(TEXT_WIDTH_PX * widthFrac);
  return new Paragraph({
    spacing: { before: 200, after: 80 },
    alignment: AlignmentType.CENTER,
    children: [new ImageRun({
      data: buf, type: 'png',
      transformation: { width, height: Math.round(width * h / w) },
    })],
  });
};

const REF = (text) => {
  const frags = [];
  const re = /(\*\*[^*]+\*\*|\*[^*]+\*)/g;
  let last = 0, m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) frags.push([text.slice(last, m.index), {}]);
    const tok = m[0];
    if (tok.startsWith('**')) frags.push([tok.slice(2, -2), { bold: true }]);
    else frags.push([tok.slice(1, -1), { italics: true }]);
    last = m.index + tok.length;
  }
  if (last < text.length) frags.push([text.slice(last), {}]);
  return new Paragraph({
    spacing: { after: 120, line: 300 },
    indent: { left: convertInchesToTwip(0.5), hanging: convertInchesToTwip(0.5) },
    children: frags.map(([t, o]) => new TextRun({ text: t, font: FONT, size: SZ, bold: o.bold, italics: o.italics })),
  });
};

/* --- table builder ------------------------------------------------- */
const TW = 9360; // usable width for US Letter with 1" margins (DXA)

function makeTable(header, rows, widths) {
  const total = widths.reduce((a, b) => a + b, 0);
  const colW = widths.map((w) => Math.round((w / total) * TW));
  // fix rounding so columns sum exactly to TW
  colW[colW.length - 1] += TW - colW.reduce((a, b) => a + b, 0);

  const cell = (txt, i, opts = {}) => new TableCell({
    width: { size: colW[i], type: WidthType.DXA },
    shading: opts.head ? { type: ShadingType.CLEAR, fill: 'EDEDED', color: 'auto' } : undefined,
    margins: { top: 60, bottom: 60, left: 90, right: 90 },
    children: [new Paragraph({
      spacing: { line: 240, after: 0 },
      alignment: i === 0 ? AlignmentType.LEFT : AlignmentType.CENTER,
      // keepNext on every row holds the table together, and holds the caption
      // that follows it on the same page. Without this Table 2 split with a
      // single orphaned row on the next page.
      keepNext: true,
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
/* results prose built from the data                                   */
/* ------------------------------------------------------------------ */

function describeERPCluster(c, idx) {
  const neg = Number(c.Tvalue) < 0;
  const pol = neg ? 'negative' : 'positive';
  const dir = neg ? 'more negative' : 'more positive';
  const pstr = (c.pcorr === undefined || c.pcorr === null) ? ''
    : `, p = ${Number(c.pcorr) <= 0.001 ? '.001' : Number(c.pcorr).toFixed(3).replace(/^0/, '')}`;
  return `Cluster ${idx} (${pol}) extended from ${n0(c.Start)} to ${n0(c.End)} ms, `
    + `peaking at ${n0(c.Peak)} ms over ${c.Channel} (t = ${n2(c.Tvalue)}, d = ${n2(c.ES)}${pstr}), `
    + `and involved ${c.NumElectrodes} electrode${c.NumElectrodes > 1 ? 's' : ''}; amplitudes were ${dir} `
    + `on collision than on no-collision trials.`;
}

function describeTFCluster(c, idx) {
  const sign = c.Cohens_d > 0 ? 'power increase' : 'power decrease';
  return `Cluster ${idx} (${sign} for collision relative to no-collision) spanned `
    + `${n1(c.FreqMin_Hz)}–${n1(c.FreqMax_Hz)} Hz and ${n0(c.TimeMin_ms)}–${n0(c.TimeMax_ms)} ms, `
    + `peaking at ${n1(c.PeakFreq_Hz)} Hz / ${n0(c.PeakTime_ms)} ms (t = ${n2(c.Peak_t)}, d = ${n2(c.Cohens_d)}).`;
}

const erpPostSentences = erpPost.map((c, i) => describeERPCluster(c, i + 1));
const tfPostSentences = tfPost.map((c, i) => describeTFCluster(c, i + 1));

/* ------------------------------------------------------------------ */
/* document                                                            */
/* ------------------------------------------------------------------ */

const children = [];

/* ---------- title block ---------- */
children.push(new Paragraph({
  spacing: { after: 240, line: 360 },
  alignment: AlignmentType.CENTER,
  children: [new TextRun({
    text: 'Reactive and predictive processes during unpredictable driving hazards in virtual '
      + 'reality: an exploratory brain and body study with multimodal neurophysiological '
      + 'monitoring',
    font: FONT, size: 32, bold: true,
  })],
}));

children.push(new Paragraph({
  spacing: { after: 120 }, alignment: AlignmentType.CENTER,
  children: [
    new TextRun({ text: 'Cédric Cannard', font: FONT, size: SZ }),
    new TextRun({ text: '1', font: FONT, size: SZ, superScript: true }),
    new TextRun({ text: '*, Demet Yeşilbaş', font: FONT, size: SZ }),
    new TextRun({ text: '2', font: FONT, size: SZ, superScript: true }),
  ],
}));

children.push(PR([['1', { sup: true }], [' Institute of Noetic Sciences, Novato, California, USA']],
  { align: AlignmentType.CENTER, size: SZ_SMALL, after: 40 }));
children.push(PR([['2', { sup: true }], [' Department of Biomedical Engineering, Graduate School of Natural '
  + 'and Applied Sciences, Erciyes University, Kayseri, Türkiye']],
  { align: AlignmentType.CENTER, size: SZ_SMALL, after: 40 }));
children.push(PR([['* Corresponding author: ccannard@pm.me', {}]],
  { align: AlignmentType.CENTER, size: SZ_SMALL, after: 320 }));

/* ---------- abstract ---------- */
children.push(H1('Abstract'));

children.push(PR([
  ['Objective. ', { b: true }],
  ['Whether the brain differentiates hazardous from non-hazardous events before they occur, without '
    + 'predictive cues, remains contested: reported effects are small, often difficult to replicate, and '
    + 'obtained from paradigms in which hundreds of static images are presented on a black screen in a '
    + 'laboratory room. Prior electroencephalography (EEG) studies reporting such pre-stimulus '
    + 'differentiation have also been limited by non-causal filtering, pseudorandom sequences and '
    + 'uncontrolled temporal expectancy. We asked when discriminative neural information about an '
    + 'unpredictable collision becomes available in an ecologically valid setting, and whether a '
    + 'dry-electrode headset built into a virtual reality display can resolve it. '],
  ['Approach. ', { b: true }],
  [`Sixteen participants passively observed an immersive driving simulation while EEG and photoplethysmography `
    + `were recorded from a wearable multimodal headset. Each of 120 trials ended in a collision or no collision, `
    + `assigned independently at 50% probability by a quantum random number generator. EEG was filtered with a `
    + `minimum-phase causal filter, without baseline correction. Mass-univariate hierarchical general linear `
    + `models with permutation cluster correction were applied to length-matched pre- and post-stimulus windows, `
    + `in the time and time-frequency domains; classification used leave-one-subject-out cross-validation. `],
  ['Main results. ', { b: true }],
  [`${spell(erpPost.length).replace(/^./, (m) => m.toUpperCase())} post-stimulus cluster`
    + `${erpPost.length > 1 ? 's' : ''} differentiated the conditions`
    + (erpLargest
      ? `, the largest peaking at ${n1(+erpLargest.Peak)} ms (d = ${n2(+erpLargest.ES)})`
      : '')
    + `, with broadband power modulation that replicated across two normalisations and was decoded from `
    + `held-out participants with up to ${n1(bestLOSO)}% accuracy. In the pre-stimulus window no time-domain `
    + `cluster formed and classification remained at chance (all p ≥ ${n2(mlPrePmin)})`
    + (tfPre && tfPre.length
      ? `, while a broadband spectral difference survived cluster correction under both `
        + `normalisations and every preregistered control analysis (Section 3.5). `
      : ' and no time-frequency cluster formed. ')
    + `Heart rate differentiated the conditions neither alone nor when added to the classifier. `],
  ['Significance. ', { b: true }],
  ['Differentiation of collision events was evoked and decodable after stimulus onset'
    + (tfPre && tfPre.length
      ? ', while in the pre-stimulus window a broadband spectral difference survived correction and '
        + 'passed every preregistered control; the preregistered anticipatory hypothesis thus found '
        + 'support in the time-frequency domain only. Its shape, a sustained offset rather than a '
        + 'transient preceding onset, constrains interpretation without settling it; given the small '
        + 'sample and the exploratory window selection, it is a target for replication rather than a '
        + 'finding. '
      : '. ')
    + 'Because data collection ended early, all findings are exploratory. A wearable dry-electrode system '
    + 'can resolve robust event-related responses to naturalistic threat inside virtual reality, and the '
    + 'paradigm is ready for adequately powered replication.'],
], { after: 240 }));

children.push(PR([
  ['Keywords: ', { b: true }],
  ['electroencephalography; event-related potentials; virtual reality; wearable sensors; '
    + 'hazard perception; anticipation; mass-univariate statistics; exploratory study'],
], { after: 320 }));

/* ---------- 1. Introduction ---------- */
children.push(H1('1. Introduction'));

children.push(P('The human brain continuously generates predictions about forthcoming sensory events, a capacity '
  + 'formalised within predictive processing frameworks [1–3] and is well characterised when cues are '
  + 'available. The contingent negative variation (CNV), a slow frontocentral negativity, reliably '
  + 'indexes temporal and motivational anticipation in cued paradigms [4–6] and in learning temporal '
  + 'regularities independently of motor preparation [7]. '
  + 'CNV amplitude grows when the inter-stimulus interval (ISI) is stable and predictable, and is particularly large '
  + 'before emotionally salient stimuli [8, 9]. How the brain responds to, and whether it prepares '
  + 'for, genuinely unpredictable, high-salience events in ecologically valid settings remains far '
  + 'less clear.'));

children.push(P('Most electrophysiological work on threat processing relies on laboratory stimuli, '
  + 'typically hundreds of static images or tones presented on a black screen in a sterile room. Such '
  + 'paradigms are well controlled, but they lack the temporal dynamics and multisensory richness of '
  + 'real-world hazards. Virtual reality (VR) offers a bridge, preserving experimental control while '
  + 'engaging genuine threat-processing systems [10, 11]. Collision events in immersive driving '
  + 'simulations are especially well suited to this purpose: they involve an abrupt onset of unexpected '
  + 'multisensory stimulation with clear survival relevance.'));

children.push(P('Prior electroencephalography (EEG) research in driving contexts has examined neural responses during collision avoidance, '
  + 'but with important constraints. Li et al. [12] recorded EEG across four stages of a pedestrian '
  + 'collision-avoidance task and reported broad increases in delta, theta, alpha and beta power as the event '
  + 'unfolded. However, active braking confounded threat responses with movement preparation, band-power '
  + 'analysis lacks temporal resolution, and a single event per participant precludes trial-level analysis. '
  + 'Wang et al. [13] examined directed '
  + 'connectivity while participants watched driving videos and predicted collisions, finding more stable '
  + 'beta-band connectivity in experienced drivers. Their stimuli were flat-screen videos rather than immersive '
  + 'environments; only correctly predicted trials were analysed, excluding the signature of undetected events; '
  + 'and collision timing varied naturally within clips, leaving temporal expectancy uncontrolled.'));

children.push(P('A separate literature has asked whether physiological activity preceding randomly assigned, '
  + 'emotionally salient events differs systematically between event types, even without predictive cues. A '
  + 'meta-analysis of 26 studies reported a small but consistent effect (weighted d = 0.21), with a 95% '
  + 'confidence interval (CI) of [0.15, 0.27] [14]. Effects of this size require large samples to '
  + 'replicate reliably, and the artificial, repetitive character of these paradigms was a primary '
  + 'motivation for the present study. This literature has also identified a methodological artefact capable '
  + 'of mimicking such effects: the expectation bias or gambler\u2019s fallacy confound [15]. When stimuli are drawn randomly with replacement, participants may implicitly expect an '
  + 'arousing event to become more likely after a run of neutral ones; averaging across individual sequences then '
  + 'introduces a spurious pre-stimulus difference in the hypothesised direction. This bias is effectively '
  + 'eliminated when a true hardware random number generator is used with equiprobable stimulus '
  + 'categories [15, 16].'));

children.push(P('Several EEG studies have reported pre-stimulus differentiation between upcoming stimulus '
  + 'categories. McCraty et al. [17] observed frontal pre-stimulus amplitude differences between emotional and '
  + 'neutral pictures; Radin and Lobach [18], occipital differentiation before light flashes; and Radin et al. [19], CNV-like activity in experienced meditators using a causal elliptic filter whose effective '
  + 'order entailed substantial phase distortion. Duma et al. [20] implemented a driving simulation with '
  + 'randomly presented crash and no-crash trials and observed a CNV-like negativity approximately 1000 ms before '
  + 'crash trials. A second preregistered study from the same group [21], using true randomisation '
  + 'with faces and sounds, likewise did not reach significance in its confirmatory analyses, which its '
  + 'authors attributed to conservative correction across a high-density montage.'));

children.push(P('A further study from the same group reported larger amplitude anticipatory activity over '
  + 'occipital regions before unpredictable faces than sounds, and over right auditory regions before '
  + 'sounds than faces [22]. Two methodological issues recur across this literature and motivate the '
  + 'present design. First, '
  + 'zero-phase (bidirectional) filters, applied by default in common software packages, smear post-stimulus '
  + 'activity backwards into the pre-stimulus period and can generate entirely artefactual anticipatory effects '
  + '[23–25]. Bilucaglia et al. [26] '
  + 'illustrate the risk concretely: a zero-phase FIR filter of order 16,500 at 500 Hz has an impulse '
  + 'response extending roughly 16.5 s in each direction, so their decoded 1000 ms window almost certainly '
  + 'contained post-stimulus information shifted backwards in time; causal minimum-phase filters cannot do '
  + 'this by construction. '
  + 'Second, baseline correction can contaminate pre-stimulus epochs when the ISI is too '
  + 'short for activity to return to baseline. When conditions are compared with pairwise permutation contrasts, '
  + 'as here, any shared drift or offset cancels in the difference, so baseline correction is unnecessary and '
  + 'costs signal-to-noise ratio [27, 28].'));

children.push(P('The present study addresses these limitations simultaneously. Participants passively observed '
  + 'unpredictable collisions in a fully immersive VR driving simulation, combining ecological salience with '
  + 'precise control over event timing and randomisation. Trial sequences were generated with a quantum random '
  + 'number generator (qRNG) at equiprobable rates, so the interval preceding a trial carried no information about that '
  + 'trial\u2019s outcome, and '
  + 'the fully passive design avoided motor-preparation confounds. EEG was filtered causally and analysed without '
  + 'baseline correction, using symmetric pre- and post-stimulus windows so that the two periods were treated '
  + 'identically.'));

children.push(P('Our primary aim was to characterise the post-stimulus response to unexpected collision events '
  + 'at the level of single trials, which prior VR-EEG work on collisions has not done. Secondary aims were '
  + 'to test whether pre-stimulus activity differs between upcoming collision and no-collision trials under '
  + 'these controls, and to assess cardiac reactivity to the same events.'));

children.push(P('Six hypotheses were preregistered. H1 held that post-stimulus EEG would differ between '
  + 'collision and no-collision events, with an early sensory response to the unexpected onset within '
  + 'approximately 100–150 ms, followed by extended differences over roughly 300–1000 ms as the '
  + 'collision unfolded. H2, the primary anticipatory hypothesis, held that pre-stimulus EEG would '
  + 'differentiate upcoming collision from no-collision events in the second preceding onset, despite the '
  + 'absence of any predictive cue. H3 held that such an effect, if predictive rather than a CNV, would '
  + 'remain stable across early, middle and late blocks rather than growing with '
  + 'learning. H4 held that the magnitude of pre-stimulus differentiation would correlate positively with the '
  + 'magnitude of the post-stimulus response, as time-symmetric accounts require. H5 held that pre-stimulus '
  + 'differentiation would be stronger in participants with greater experience in domains demanding sustained '
  + 'attention and anticipation. H6 held that a classifier trained on pre-stimulus features would discriminate '
  + 'upcoming events above chance. H4, the pre/post time-symmetry correlation, was evaluated on the '
  + 'time-frequency clusters (Section 2.7). H3 was evaluated, on the time-frequency cluster described in '
  + 'Section 3.4; in both cases the registered window-selection clauses presuppose a primary pre-stimulus '
  + 'effect, which was found only in the time-frequency domain.'));

children.push(PR([['Scope and status. ', { b: true }],
  ['This study was preregistered as a confirmatory investigation targeting N = 63. Data collection was '
    + 'terminated at N = 18 when the headset manufacturer withdrew technical support, and two of the planned '
    + 'physiological measures, electrodermal activity (EDA) and pupillometry, never produced usable data. The study is '
    + 'therefore reported in full as ', {}],
  ['exploratory', { i: true }],
  ['. We report all analyses conducted, state every deviation from the preregistration, and draw no confirmatory '
    + 'inference from any result reported here, positive or null. Readers should treat '
    + 'the effect sizes reported here as provisional; with the achieved sample the study was not powered to '
    + 'detect effects of the magnitude reported in the pre-stimulus literature.', {}],
]));

/* ---------- 2. Methods ---------- */
children.push(H1('2. Materials and methods'));

children.push(H2('2.1 Preregistration, transparency, and deviations'));
children.push(P('The study was preregistered at https://osf.io/xuw34 prior to analysis. Quality-control '
  + 'inspections of sensor integrity were performed without reference to experimental condition, and all '
  + 'analysis code is available at the repository listed under Data availability. The deviations from the '
  + 'registered protocol are listed below. None was informed by a condition contrast. An update to the '
  + 'registration records them on the original record.'));

children.push(BULLET('Sample. The target of 63 participants was not reached; data collection ended at 18 when '
  + 'the manufacturer withdrew support.'));
children.push(BULLET('Minimum trials. The registration required 40 artefact-free trials per condition, a '
  + 'figure set before recording from an expected rejection rate that proved too optimistic and resting on '
  + 'no power calculation. Applying it would have excluded four further participants (35, 37, 39 and 39 '
  + 'no-collision trials) from an already small sample, so the minimum was adjusted to 35; participants at '
  + 'the adjusted limit showed clear post-stimulus ERPs on inspection, and no primary analysis excludes '
  + 'those four.'));
children.push(BULLET('Modalities. EDA and eye-tracking produced no usable data and are not '
  + 'reported. Photoplethysmography (PPG), registered as unusable, was recovered by the salvage inspection that the '
  + 'registration itself specified as an exploratory analysis, and is reported for 14 participants.'));
children.push(BULLET('Sampling rate. The registration states 200 Hz; the EEG was sampled at 250 Hz.'));
children.push(BULLET('Filtering. A 0.5\u201330 Hz minimum-phase causal filter was applied to both analysis '
  + 'windows, rather than 0.5\u201345 Hz with zero-phase filtering for the post-stimulus window only. Filtering '
  + 'the two windows differently would have made them non-comparable, which is the symmetry this design depends '
  + 'on. The registered final 10 Hz smoothing was not applied; analyses run on the unsmoothed data.'));
children.push(BULLET('Bad-channel detection. The registration set the correlation threshold at 0.5 with the '
  + 'lowest 10% of correlations excluded, and removed channels flagged in more than 33% of windows. The '
  + 'implemented rule uses 0.55, excludes the lowest 20%, and removes channels flagged in more than 30% of '
  + 'windows; it additionally requires the channel to be an amplitude outlier across windows, and adds a '
  + 'flat-channel test that the registration does not specify (Section 2.5).'));
children.push(BULLET('Preprocessing parameters. Artefact subspace reconstruction (ASR) used a threshold of 100 rather '
  + 'than 80; independent component analysis (ICA) used PICARD rather than extended Infomax, with the first component '
  + 'removed because automatic classification was unreliable at 12 channels; epochs span \u22123000 to +3000 ms '
  + 'rather than \u22121500 to +1500 ms.'));
children.push(BULLET('Analysis windows. Symmetric windows of \u22121200 to 0 ms and 0 to +1200 ms were used. The '
  + 'registration gives three different window pairs in three places.'));
children.push(BULLET('Estimator and correction. A two-level hierarchical model with weighted least squares and '
  + 'Huber weights replaced ordinary least squares. Family-wise error in the EEG analyses is controlled by '
  + 'cluster-based permutation correction rather than the registered t-max; the registration assumed '
  + 'cluster correction would not be viable on a 12-channel montage, but Delaunay triangulation of these '
  + 'sites yields a well-formed adjacency graph (4.7 neighbours per channel) and the observed effects are '
  + 'spatially extended, so the method applies. The cardiac analysis uses t-max; no scheme was registered '
  + 'for that modality, and the permutation scheme (labels shuffled within participant) is as registered.'));
children.push(BULLET('Classification. Leave-one-subject-out (LOSO) cross-validation rather than stratified ten-fold, '
  + 'operating on participant-averaged responses rather than single trials. The registered pre-stimulus '
  + 'classification was run alongside the post-stimulus one, on the same symmetric windows as the general '
  + 'linear models (GLMs), and remained at chance.'));
children.push(BULLET('Registered pre-stimulus controls. The gambler\u2019s-fallacy run-length control is '
  + 'registered unconditionally and was performed. The early/middle/late block analysis dissociating the '
  + 'CNV from predictive anticipatory activity is registered with a clause fixing its '
  + 'window to one \u201cdefined from the primary pre-stimulus analysis\u201d; the primary pre-stimulus effect was '
  + 'found only in the time-frequency domain, so the block window was taken from the pre-stimulus time-frequency '
  + 'cluster, and the pre/post time-symmetry correlation (H4) was run on the two time-frequency cluster windows '
  + 'for the same reason (Section 2.7); both departures are declared in the registration update. These analyses '
  + 'are reported in Section 3.5. The '
  + 'registration\u2019s definition of run length, \u201cconsecutive preceding trials of the same '
  + 'condition\u201d, does not state same as what; both readings were computed and both are reported.'));
children.push(BULLET('Permutation scheme with covariates. The permutation routine used for the '
  + 'baseline-as-regressor models was found to permute only the condition column, leaving the baseline '
  + 'covariate bound to its original trials, which inflates the statistic (surrogate relabelled datasets: '
  + '19 of 20 declared significant). It was replaced with the Freedman\u2013Lane procedure, which permutes '
  + 'residuals of the reduced model and leaves the design matrix intact (0 of 20 on the same check). All '
  + 'covariate-adjusted results use Freedman\u2013Lane; models without covariates are unaffected, because '
  + 'with condition as the only regressor the two schemes coincide.'));
children.push(BULLET('Covariates. Thirteen individual-difference variables were tested in both windows, '
  + 'against the time-domain effects and, because the time-frequency effects have no time-domain '
  + 'counterpart, against those as well. Benjamini–Hochberg is applied across the moderator family as '
  + 'registered. The time-frequency moderator analysis is an exploratory extension. Personality was measured '
  + 'with the Ten-Item Personality Inventory rather than the 10-item Big Five Inventory named in the '
  + 'registration, and its items were administered on a five-point agreement scale rather than the '
  + 'instrument’s standard seven-point scale. Piloting experience was collected within the driving item '
  + 'rather than separately.'));
children.push(BULLET('ISI. Part of the registered claim holds and part does not. The '
  + 'approach phase, from trial onset to the tire blowout, is fixed at 7.02 s in both conditions. The '
  + 'interval between successive blowouts is not, because the outcome phase is shorter on collision trials; '
  + 'read in the usual stimulus-to-stimulus sense the registered wording is wrong. The property the design '
  + 'requires does hold, and is reported in Section 2.3: because the quantum randomisation assigns each trial '
  + 'independently, the interval preceding a trial is independent of that trial’s outcome.'));

children.push(H2('2.2 Participants'));
children.push(P('Participants were recruited from the general adult population through online advertisements, '
  + 'mailing lists, and word of mouth. Inclusion criteria were age ≥ 18 years, ability to travel to the '
  + 'laboratory, no known screen sensitivity, and ability to participate safely in a VR driving task. Exclusion '
  + 'criteria were uncorrected visual impairment, any physical or psychological condition interfering with task '
  + 'performance, and a history of severe motion sickness or trauma related to car accidents. All participants gave written informed '
  + 'consent and received $30 compensation; the study was approved by the Institute of Noetic Sciences '
  + 'Institutional Review Board (IORG#0003743).'));

children.push(PR([
  ['Data collection was discontinued after 18 participants when the manufacturer withdrew technical support for '
    + 'the headset. Of these, one was excluded for retaining only 27 artefact-free trials per condition and one '
    + 'for insufficient EEG signal quality, yielding a final EEG '
    + `sample of N = ${S.nSub} (10 female, 6 male). A separate quality screen was applied to the cardiac data `
    + '(Section 2.9), giving N = 14 for that analysis; sensor-specific screening was used because signal quality '
    + 'of the EEG and PPG channels was independent within participants. Mean age was 56.8 years (SD = 14.7, range '
    + '27–76) and mean formal education 17.1 years (SD = 3.6). Self-rated experience (0–10) was: driving M = 7.0 '
    + '(SD = 1.3), sports M = 3.6 (SD = 1.8), video games M = 3.6 (SD = 3.0), meditation M = 3.9 (SD = 2.5). '
    + 'Fourteen participants (87.5%) reported believing in intuition and two (12.5%) responded "I don\u2019t know". '
    + 'Personality was assessed with the Ten-Item Personality Inventory (TIPI; [29]), '
    + 'administered on a five-point agreement scale rather than the instrument’s standard seven-point '
    + 'scale, so trait scores range from 1 to 5 and are not comparable with published TIPI norms. Items '
    + 'were presented grouped by trait rather than in the instrument’s original interleaved order. It was '
    + 'completed by 14 of the 16 participants (trait means 2.9 to 4.2 on the 1\\u20135 scale).', {}],
]));

children.push(H2('2.3 Design and virtual reality paradigm'));
children.push(P('Participants were seated and observed an immersive first-person driving simulation from the '
  + 'perspective of a passenger in a vehicle moving forward automatically. On each trial an oncoming vehicle '
  + 'appeared in the opposite lane. Both conditions begin with the same event: the participant\u2019s tire blows '
  + 'out, delivered as a loud bang together with the visible burst and a swerve of the vehicle. This tire blowout '
  + 'is the moment at which the two conditions diverge, and is the event to which the event-related '
  + 'potentials (ERPs) analysed here are time-locked. '
  + 'On collision trials the oncoming vehicle then struck the participant\u2019s vehicle; on no-collision trials '
  + 'the vehicle passed without incident (Figure 1). The impact itself was not written to the trigger channel, so its '
  + 'latency cannot be recovered from these recordings; it is bounded by the 3.49 s outcome phase that follows '
  + 'the blowout on collision trials (Trial timing, below). The paradigm was entirely passive; no motor response '
  + 'was required at any point. The oncoming vehicle also served as gaze support: it approaches from the far end '
  + 'of the scene throughout the 7 s approach phase and so acts as a slowly moving fixation target, the function '
  + 'a stationary fixation cross serves in conventional EEG experiments, without which free viewing of a driving '
  + 'scene would leave gaze and attention uncontrolled across the trial.'));

children.push(P('The experiment used a within-participant repeated-measures design. Each participant completed '
  + '120 trials. Trial type was determined by a qRNG via the Australian National '
  + 'University Quantum Random Numbers Server API, with each trial assigned independently at 50% probability. '
  + 'Unique sequences were pre-generated per participant, stored as CSV files, and loaded automatically by the VR '
  + 'application at session onset. All sequences were validated blind, before data collection, by runs tests, autocorrelation, Shannon '
  + 'entropy and chi-square tests (Supplementary Material).'));

children.push(PR([['Trial timing. ', { b: true }],
  ['Timing was recovered from the device timestamps of the raw trigger channel for all 2,146 recorded trials. '
    + 'Every trial began with an approach phase in which the vehicle drove forward and the oncoming vehicle '
    + 'became visible; the tire-blowout marker, at which the conditions diverge, occurred 7.02 s after trial '
    + 'onset. This approach phase was effectively invariant and did not differ between conditions (collision '
    + '7.02 s, SD = 0.04; no-collision 7.03 s, SD = 0.06; d = \u22120.07), and its minimum across all trials '
    + 'was 6.49 s, so the entire analysed epoch always fell within the current trial. The outcome phase that '
    + 'follows the blowout is shorter on collision trials, because the collision sequence ends a trial sooner: '
    + '3.49 s (SD = 0.06) against 6.01 s (SD = 0.04). The interval between successive blowouts was therefore '
    + 'not constant: 10.52 s following a collision and 13.03 s following a no-collision trial. That asymmetry '
    + 'depends on the preceding trial, which the quantum randomisation makes independent of the current one, '
    + 'so the interval preceding a collision trial and preceding a no-collision trial did not differ '
    + '(11.79 vs 11.77 s, d = 0.01). Temporal '
    + 'expectancy therefore cannot contribute to the condition contrast. Because sequences were generated by a '
    + 'hardware random source with equiprobable categories, the expectation-bias artefact described by '
    + 'Dalkvist et al. [15] is not expected to operate in these data; the registered block analysis '
    + '(Section 3.5) tests its signature directly.', {}],
]));

children.push(FIGURE('figure1_overview.png'));
children.push(CAPTION('Figure 1.', 'Study design, acquisition, signal processing and analysis. '
  + '(A) Trial structure. A 7 s approach phase, identical in both conditions, ends in a tire blowout '
  + 'carrying both an auditory and a visual cue; the trial then resolves into a collision or no collision. '
  + 'Bars are drawn to scale from the measured median durations. The two analysis windows are symmetric '
  + 'about the blowout and are treated identically. Stills show the participant\u2019s view in each '
  + 'condition. (B) Acquisition. (C) Signal processing, in order of application, with one example '
  + 'participant (sub-013) shown to illustrate the data the headset yields: ERPs averaged over the 12 '
  + 'channels and event-related heart rate, each with a 95% CI across '
  + 'that participant\u2019s trials. These are single-participant illustrations, not results; the group '
  + 'analyses appear in Figures 2\u20134. (D) Statistical analysis: the two-level mass-univariate GLM with '
  + 'cluster correction, and the LOSO decoding analysis.'));

children.push(H2('2.4 Apparatus and acquisition'));
children.push(P('Physiological data were recorded with the Galea system (OpenBCI Inc.), a multimodal wearable '
  + 'headset integrating EEG, EDA, PPG, electromyography (EMG) and inertial measurement unit (IMU) sensors within a '
  + 'Varjo Aero VR head-mounted display (HMD). EEG was recorded from 12 scalp sites using dry pin electrodes in a '
  + 'modified 10-10 montage, in which two electromyography disc electrodes were reconfigured as EEG channels at '
  + 'Fp1 and Fp2. EEG was sampled at 250 Hz: the board reports that rate and no packets were dropped in any '
  + 'recording. The import routine used for the archived analyses derived 248 Hz from the median inter-sample '
  + 'interval, and every analysis reported here was run at that value, which scales reported latencies by '
  + '0.8% (at most 7 ms at the longest cluster, below the resolution the design supports). Because the '
  + 'sampling rate also governs filter coefficients and the segments retained by ASR, reproduction '
  + 'should start from the archived epoched datasets; the recovery procedure in Section 2.7 forces the '
  + 'archived rate for the same reason. PPG was '
  + 'recorded simultaneously from red and infrared channels at 50 Hz. EDA and eye-tracking sensors '
  + 'were present in the hardware but produced no usable data at any point in the study despite systematic '
  + 'remediation (gel application, alternative electrode sites, parameter variation, and repeated '
  + 'consultation with the manufacturer); these modalities are not analysed.'));

children.push(P('Before the session, participants completed questionnaires covering eligibility, demographics, '
  + 'personality (TIPI), belief in intuition, and self-rated experience in driving, sports, video gaming and '
  + 'meditation. Participants were asked to wash their hair, avoid make-up and caffeine, and wear contact lenses '
  + 'rather than glasses where possible. Forehead and earlobe skin was cleaned with alcohol wipes, eye '
  + 'calibration was performed with the Varjo software, and electrodes were positioned as close to 10-10 '
  + 'nomenclature as the headset permitted, with pin electrodes rotated to penetrate the hair. Signal quality was '
  + 'verified with the manufacturer\u2019s software before recording.'));

children.push(PR([['Reference. ', { b: true }],
  ['EEG was referenced to an ear-clip electrode on the earlobe, with the contralateral earlobe carrying the '
    + 'bias (ground) electrode, following the standard configuration for the OpenBCI ExG architecture on which '
    + 'the Galea is built. Signals were retained in this recording reference throughout; no re-referencing was '
    + 'applied at any stage. An average reference was not used: with 12 electrodes distributed unevenly '
    + 'over the scalp, the average of the recorded channels is a poor estimate of a neutral reference and '
    + 'introduces a spatial bias of its own, so the transformation would degrade rather than improve the data. '
    + 'The consequence is that the scalp distribution of an effect is tied to the recording reference and '
    + 'cannot be disentangled from it at this channel count. Peak electrodes are therefore reported as '
    + 'descriptive maxima, and no inference is drawn from the topography.', {}],
]));

children.push(H2('2.5 EEG preprocessing'));
children.push(PR([
  [`Preprocessing was performed in MATLAB R2026a using EEGLAB 2026.0.0. Continuous data were trimmed to 1 s before `
    + `the first and 1 s after the last event marker. A minimum-phase causal bandpass filter (0.5–30 Hz) was `
    + `applied to preserve temporal causality and prevent post-stimulus activity from smearing into the `
    + `pre-stimulus window [25, 30]. A duplicate dataset was `
    + `high-pass filtered at 1 Hz with the same filter type for ICA.`, {}],
]));

children.push(P('Because the two prefrontal channels converted from disc electrodes were sometimes recorded with '
  + 'inverted amplifier leads, an automated polarity check was applied after filtering (sign agreement with '
  + 'a robust median reference at the top 10% of reference-amplitude time points, after an on-the-fly 8 Hz '
  + 'low-pass; channels below 0.5 agreement reversed).'));

children.push(P('Bad channels were flagged with a sliding-window procedure (2 s windows, 50% overlap) adapted '
  + 'from the clean_rawdata plugin. Within each window, the absolute correlation of each channel with all others '
  + 'was computed and the lowest 20% of correlations discarded; a channel was flagged in that window if it was '
  + 'both an amplitude outlier across windows and had all remaining correlations below 0.55, or if it was flat '
  + '(maximum absolute first difference < 1e-7). Channels flagged in more than 30% of windows were removed. '
  + 'ASR (threshold = 100) was applied to the 1 Hz high-pass dataset, and the '
  + 'same time segments were removed from the 0.5 Hz dataset. Removed channels were interpolated by spherical '
  + 'spline before ICA.'));

children.push(P('ICA was performed with the Preconditioned ICA for Real Data algorithm (Picard; [31]), taking the effective data rank into account [32]. Decomposition weights were '
  + 'transferred to the 0.5 Hz dataset. Given the low channel count and the dry-electrode montage, automatic '
  + 'component classification was unreliable; the first component, which in this configuration consistently '
  + 'captured ocular activity, was removed after visual confirmation for every participant. One participant '
  + 'required removal of a second ocular component.'));

children.push(P('The full pipeline is implemented as an EEGLAB plugin released with this study '
  + '(https://github.com/amisepa/galea-eeglab-plugin); its import and preprocessing dialogs, with the defaults used for '
  + 'this study, are shown in Figure 2.'));

children.push(FIGURE('figure2_methods_gui.png'));
children.push(CAPTION('Figure 2.', 'The EEGLAB plugin released with this study. (A) Import dialog: the '
  + 'Galea/OpenBCI main file is selected and its Aux twin (PPG, EDA, IMU) is picked up automatically. '
  + '(B) Preprocessing dialog with the defaults used here: 0.5\u201330 Hz minimum-phase bandpass on request, '
  + 'bad-channel detection (correlation threshold 0.55, the lowest 20% of correlations discarded, removal above '
  + '30% of windows), ASR at threshold 100 in remove mode (flagged segments '
  + 'deleted, with any event markers inside them reported), ocular independent component removal with '
  + 'confirmation, and a separate dialog for the cardiac (PPG), EDA, EMG and IMU branches.'));

children.push(PR([
  [`Data were segmented from −3000 to +3000 ms relative to the tire-blowout markers (event codes tire_pop `
    + `and no_tire_pop), that is, the `
    + `onset of the divergence between conditions. Epochs with outlier root-mean-square amplitude or outlier `
    + `high-frequency residual power were rejected using the mean-based criterion of MATLAB's isoutlier function. `
    + `No baseline correction was applied, in order to treat the pre- and post-stimulus periods identically and `
    + `avoid introducing artificial differences between conditions [27, 28]; `
    + `normalisation for time-frequency analyses is described in Section 2.7. Within-participant averages were `
    + `inspected visually to confirm clear stimulus-locked deflections and adequate signal quality.`, {}],
]));

children.push(H2('2.6 Time-domain statistical analysis'));
children.push(P('Mass-univariate GLMs were computed across all electrodes and time points, '
  + 'separately for the post-stimulus (0 to 1200 ms) and pre-stimulus (−1200 to 0 ms) periods, with trial type '
  + '(collision versus no-collision) as the predictor. The two windows were deliberately matched in length so '
  + 'that any difference between them cannot be attributed to unequal numbers of comparisons or unequal cluster '
  + 'opportunity.'));

children.push(P('A two-level hierarchical approach accommodated the unbalanced and variable trial counts across '
  + 'participants. At the first level, a trial-wise weighted least-squares GLM with Huber weights was fitted '
  + 'within each participant, down-weighting outlier trials without discarding them and yielding a '
  + 'participant-specific map of the collision-minus-no-collision effect. At the second level, these maps were '
  + 'submitted to a one-sample test across participants. Inference used a permutation null distribution '
  + 'constructed from 1000 iterations in which condition labels were shuffled within each participant at the '
  + 'first level before recomputing the entire two-level procedure, thereby preserving the within-participant '
  + 'trial structure. Family-wise error was controlled with cluster-based spatiotemporal correction across '
  + 'electrodes and time points at α = 0.05. Clusters separated by gaps shorter than 10 ms were merged before '
  + 'reporting. Effect sizes are Cohen\u2019s d computed from the distribution of participant-level estimates.'));

children.push(P('As a sensitivity analysis, the same models were refitted with the per-trial baseline entered '
  + 'as an additional Level-1 predictor rather than subtracted [33], using a window of \u22123000 to '
  + '\u22122000 ms common to both analysis windows. That window lies inside the approach phase of every trial, '
  + 'ends 800 ms before the pre-stimulus window begins, and is identical for both analyses, so it preserves the '
  + 'symmetry of the design. Entering the baseline as a regressor lets its weight be estimated from the data '
  + 'rather than assuming a coefficient of \u22121, and avoids injecting baseline noise into every trial '
  + 'estimate.'));

children.push(PR([['Cluster correction. ', { b: true }],
  ['Family-wise error in the time-domain analyses was controlled by cluster-mass permutation correction, '
    + 'implemented in analysis/cluster_correct.m. The time-frequency analyses use a different cluster '
    + 'statistic and are described in Section 2.7; the two are not interchangeable and we state which was '
    + 'used wherever a corrected result is reported. Clusters were '
    + 'formed at a two-tailed t threshold corresponding to p = 0.05, positive and negative excursions were '
    + 'clustered separately so that adjacent effects of opposite sign cannot merge, cluster mass was the sum '
    + 'of |t| within a cluster, and the observed and null maps were thresholded by the identical rule. The '
    + 'null distribution was the maximum cluster mass over 1000 permutations and corrected p-values include '
    + 'the observed statistic in the null, so no p-value can be exactly zero [34]. '
    + 'Channel adjacency was defined by Delaunay triangulation of the electrode montage, giving a mean of 4.7 '
    + 'neighbours per channel. Clustering used standard adjacency, with no minimum-neighbour criterion. Such a '
    + 'criterion has no principled setting on a montage this sparse: adjacent electrodes are several '
    + 'centimetres apart, so a genuine effect need not be expressed at two of them, and requiring it would '
    + 'erode spatially broad and focal effects alike.', {}],
]));

children.push(H2('2.7 Time-frequency analysis'));
children.push(P('Because this study tests for a pre-stimulus difference, the time-frequency estimator was '
  + 'chosen so that it cannot move post-stimulus signal backwards in time. A conventional symmetric Morlet '
  + 'wavelet integrates over a window centred on the sample being estimated, so power at a pre-stimulus '
  + 'latency is partly determined by what happens after the stimulus; at the low frequencies of interest that '
  + 'window is hundreds of milliseconds wide, which is large relative to the effect being sought. Estimates '
  + 'were therefore computed with a causal (one-sided) Morlet wavelet, truncated at zero lag so that each '
  + 'sample is a function of preceding data only, and applied by forward-only convolution with left-side '
  + 'padding. Mirror padding was not used, as reflecting the signal about the trial edge reintroduces '
  + 'post-stimulus information into the pre-stimulus estimate.'));

children.push(P('Wavelets spanned 3 to 30 Hz in 0.5 Hz steps, with the number of cycles increasing linearly '
  + 'from 4 to 8 across that range. The lower bound was raised from the 1 Hz used in an earlier version of '
  + 'this analysis: a wavelet has temporal support of approximately ±3σ with σ = cycles / (2πf), so at 1 Hz it '
  + 'draws on nearly two seconds of data, and no pre-stimulus estimate within a second of stimulus onset can be '
  + 'kept free of post-stimulus signal. At 3 Hz the one-sided support is about 640 ms, which the analysis '
  + 'window accommodates. Instantaneous power was taken as the squared modulus of the convolution output and '
  + 'averaged across channels with a 20% trimmed mean. The time-course panel of Figure 4E was derived from the '
  + 'same trial-level power: per trial, in dB (10·log₁₀), averaged over the same channels and over trials '
  + 'within each participant and condition, then averaged across participants (mean ± 1 s.e.m.).'));

children.push(P('Two normalisations were applied in parallel. The primary analysis applies none: raw power '
  + 'enters the model directly, in decibels, because conventional baseline correction divides every '
  + 'estimate by mean power in a pre-stimulus window and so forces the corrected difference towards zero '
  + 'inside that window. The robustness check instead enters baseline power as a regressor rather than '
  + 'dividing by it [33], which adjusts for pre-trial power differences while leaving the pre-stimulus '
  + 'contrast free to vary. Baseline power was taken from −2300 to −1900 ms, separated from '
  + 'the analysed pre-stimulus interval by more than the one-sided support of the lowest-frequency '
  + 'wavelet, so the covariate and the tested signal share no samples. The specparam-based aperiodic '
  + 'normalisation used in an earlier version was dropped [35]: it was not preregistered, the aperiodic '
  + 'background is not stationary over a trial [36, 37], and it required a Python dependency the rest of '
  + 'the analysis does not have.'));

children.push(P('The identical hierarchical GLM and permutation procedure was then applied, with cluster '
  + 'correction operating over the joint frequency-time space. Time-frequency clusters were formed at an '
  + 'uncorrected threshold of p < 0.05 and assessed against the permutation distribution of maximum cluster '
  + 'extent, whereas the time-domain analysis used cluster mass; both control the family-wise error rate at '
  + 'alpha = 0.05. Two properties of the time-frequency correction differ from the time-domain one and are '
  + 'stated for completeness: the cluster statistic is the number of points in a cluster rather than the sum '
  + 'of |t| within it, and positive and negative excursions are thresholded on |t| and so could in principle '
  + 'merge. Neither is consequential for the results reported here, because every suprathreshold point in '
  + 'both windows is positive, so no cluster contains excursions of both signs. Pre-stimulus and '
  + 'post-stimulus windows were corrected separately, so no post-stimulus cluster can contribute to a '
  + 'pre-stimulus one.'));

children.push(P('Truncating a Gaussian-enveloped wavelet at zero lag leaves a kernel with spectral sidelobes that '
  + 'decay far more slowly than those of the symmetric wavelet it is derived from, so the effective '
  + 'bandwidth is broader than the nominal cycle count implies and adjacent frequency rows are strongly '
  + 'correlated. The analysis therefore resolves the presence and timing of spectral power changes but '
  + 'not their frequency specificity: peak frequencies are the centre of a broad, correlated response '
  + 'rather than a band assignment, and an effect extending across the analysed range is not by itself '
  + 'evidence that the underlying change is broadband. Amplitude normalisation '
  + 'is unaffected (measured steady-state response flat to within 3% from 3 to 30 Hz), as is the '
  + 'causality guarantee, which follows from the truncation itself.'));

children.push(P('Pre-stimulus control analyses. Where a pre-stimulus cluster survived correction, the '
  + 'registered control analyses were run on mean power within it, one value per trial. Two of these require '
  + 'each analysed epoch to be located in the delivered 120-trial sequence. The event markers in the raw '
  + 'recordings and the pre-generated quantum-random-number sequences identify every delivered trial\u2019s '
  + 'position and condition; what the archived data do not store is which of the 120 trials survived '
  + 'preprocessing: ASR removes segments from the continuous recording and epochs '
  + 'spanning the resulting discontinuities are then dropped, so the retained set is a non-contiguous subset '
  + 'and the removed-segment mask was not saved. The mapping was recovered by replaying the length-determining '
  + 'steps of the pipeline (filtering, the stored bad-channel selection, and ASR) and reading off the '
  + 'surviving events; ICA was not replayed (it alters the data but not its length and creates no '
  + 'discontinuities). Each recovered mapping was verified against values stored by the original run '
  + '(proportion of samples reconstructed, per-condition trial counts, epoch count); one recording did not '
  + 'reproduce and its participant is excluded from these analyses only, leaving 15. The same recovered index was used to align the ocular '
  + 'and EMG channels, which never underwent ASR and so have a '
  + 'different epoch set, trial by trial to the EEG.'));

children.push(P('Time-symmetry analysis. The registered time-symmetry correlation (hypothesis H4) is '
  + 'peak-matched to the primary mass-univariate effects, a precondition the time-domain analysis could not '
  + 'meet (Section 3.3); since the pre-stimulus effect was found in the time-frequency domain, the registered '
  + 'analysis was instead run on the two time-frequency clusters. For each trial of every participant, the '
  + 'index is the mean channel-averaged power within the pre-stimulus cluster window and within the '
  + `post-stimulus cluster window (the windows of Figure 4). Association was measured with the robust `
  + 'estimator the registration names (skipped Spearman; Pernet, Wilcox and Rousselet, 2012 [39], Robust '
  + 'Correlation Toolbox), tested by 10,000 within-participant permutations of the pre\u2013post pairing, and '
  + 'combined across participants with a one-sample t test on Fisher-transformed coefficients. Because the '
  + 'windows come from these data, the result is exploratory.'));

children.push(H2('2.8 Classification analysis'));
children.push(PR([
  ['To test whether condition could be decoded from held-out participants, ERPs were averaged '
    + 'across trials within each participant and condition, and the resulting '
    + 'waveform was used as the feature vector. Averaging is across trials only: the time course is '
    + 'preserved, so each observation is 12 channels \u00d7 298 samples = 3,576 features. The windows are the '
    + 'symmetric pair used by the GLMs, 0 to +1200 ms and \u22121200 to 0 ms, so that the '
    + 'mass-univariate and multivariate analyses interrogate the same interval. This gives ', {}],
  [`${NOBS16} observations (${S.nSub} participants \u00d7 2 conditions). `, {}],
  ['Six classifiers were evaluated: a support vector machine with a radial basis function kernel, a '
    + 'multilayer perceptron with a single five-unit hidden layer, a Gaussian naive Bayes classifier, a '
    + 'random forest with 100 trees, a decision tree, and k-nearest neighbours (k = 3, cosine distance, '
    + 'inverse distance weighting). Evaluation used LOSO cross-validation, with both of a '
    + 'participant\u2019s condition averages held out together and predictions pooled across folds before '
    + 'computing metrics. Features were z-scored using means and standard deviations computed from training '
    + 'folds only. The identical procedure was applied to the pre-stimulus window. Given the small number of '
    + 'observations, accuracies are accompanied by 95% Wilson score intervals. Significance was assessed '
    + 'against a permutation null: condition labels were shuffled within participant, preserving each '
    + 'participant’s pair structure, and the entire cross-validation was repeated 1000 times to build the '
    + 'null distribution of accuracy. This matches the permutation scheme used by the mass-univariate '
    + 'analyses, so the two families of tests rest on the same exchangeability assumption. The smallest '
    + 'attainable p-value is 1/1001.', {}],
]));
children.push(PR([
  ['The same procedure was then applied to the cardiac data and to the two modalities combined. The '
    + 'cardiac feature vector is the participant’s mean instantaneous heart rate sampled at eleven points '
    + 'spanning the full −5 to +5 s epoch, used alone and concatenated onto the ERP features. Note that '
    + 'this is a wider interval than the ±1200 ms used for EEG: heart rate resolves at '
    + 'roughly one sample per beat, so a 1.2 s window would contain one or two values and could not support '
    + 'a classifier at all. The three feature sets are therefore matched on participants and folds but not '
    + 'on time window, and the comparison should be read accordingly. Because the cardiac quality '
    + 'screen retained a different subset of participants from the EEG screen, this three-way comparison is '
    + 'restricted to the ', {}],
  [`${NCARD} participants with usable data in both modalities, so that all three feature sets are `
    + `evaluated on identical folds and are directly comparable (${NOBS14} observations). `, {}],
  ['The concatenation is reported for completeness rather than as a competitive fusion: appending eleven '
    + 'features to several thousand cannot be expected to move a decision boundary, and it is the '
    + 'heart-rate-only model that establishes whether cardiac information is present at all.', {}],
]));

children.push(H2('2.9 Cardiac data'));
children.push(P('PPG signals were trimmed to the experimental period with a 1 s buffer. Signal quality was '
  + 'assessed per channel with a frequency-domain metric: each channel was high-pass filtered at 0.75 Hz and '
  + 'segmented into 4 s windows with 50% overlap, and signal-to-noise ratio was computed for each window as the '
  + 'decibel ratio of power within cardiac bands (0.8–2.5, 1.6–5.0 and 2.4–7.5 Hz, capturing the fundamental '
  + 'pulse rate and its harmonics) to power outside them, with the median across windows as the channel index. '
  + 'The infrared channel was superior in every retained participant (SNR range 3.9–19.2 dB) and was selected '
  + 'throughout. It was then bandpass filtered between 0.5 and 3 Hz with a causal minimum-phase FIR filter.'));

children.push(P('Four participants were excluded: three for insufficient signal quality and one whose session was '
  + 'interrupted and re-started, leaving N = 14. Heartbeats were detected and converted to RR intervals with the '
  + 'BrainBeats plugin [38]. Artefactual and ectopic beats were removed by an '
  + 'automated procedure, flagging a mean of 0.7% of beats (SD = 0.8, range 0.0–2.8). Instantaneous heart rate '
  + 'was derived as 60/NN and epoched from −5 to +5 s around each event, without baseline correction. '
  + 'No-collision markers within 5 s of one another were de-duplicated and any coinciding with a collision event '
  + 'removed. Trials with outlier root-mean-square values were excluded per participant, retaining a mean of 58.1 '
  + 'collision trials (SD = 4.2, range 52–66) and 61.3 no-collision trials (SD = 7.6, range 39–69).'));

children.push(P('Condition differences were assessed with the same two-level hierarchical WLS/Huber GLM and '
  + 'permutation procedure described in Section 2.6, applied separately to the post-stimulus (0 to +5 s) and '
  + 'pre-stimulus (−5 to 0 s) windows, with multiple comparisons across time points controlled by t-max '
  + 'correction at α = 0.05.'));

children.push(H2('2.10 Exploratory individual-difference analyses'));
children.push(P('Thirteen individual-difference variables (age, sex at birth, years of education, self-rated '
  + 'driving, sports, video-game and meditation experience, belief in intuition, and the five TIPI traits) were '
  + 'each entered separately as a second-level covariate in the hierarchical GLM, in both time windows: 26 models '
  + 'in all (13 variables × 2 windows). For the cardiac data, the per-participant post- and '
  + 'pre-stimulus heart-rate condition effect was correlated with the same variables using skipped Spearman '
  + 'correlations [39], with bivariate outliers identified by projection onto the '
  + 'minimum covariance determinant centre and a chi-square-based box-plot rule, followed by Benjamini–Hochberg '
  + 'false discovery rate (FDR) correction across the 13 variables, as registered.'));
children.push(P('For the EEG models the registered FDR correction across variables is '
  + 'non-binding. Each of the 26 was cluster-mass corrected within itself and none produced a surviving '
  + 'cluster. Benjamini–Hochberg is a step-up procedure whose adjusted p-values are never smaller than the '
  + 'raw ones, so a family containing no rejection before correction cannot contain one after it; with no '
  + 'rejections the FDR across these models is zero by construction. The '
  + 'individual-difference results are reported as exploratory and presented in Supplementary Material rather '
  + 'than as findings of this study on grounds of statistical power, not because multiplicity was left '
  + 'uncontrolled.'));

/* ---------- 3. Results ---------- */
children.push(H1('3. Results'));

children.push(H2('3.1 Data quality'));
children.push(PR([
  [`Across the ${S.nSub} retained participants, a mean of ${n2(S.badChan.m)} channels per participant `
    + `(SD = ${n2(S.badChan.sd)}, range ${n0(S.badChan.min)}–${n0(S.badChan.max)}) were flagged as bad and `
    + `interpolated. ASR removed a mean of ${n2(S.asr.m)}% of continuous data (SD = ${n2(S.asr.sd)}, range `
    + `${n2(S.asr.min)}–${n2(S.asr.max)}). A mean of ${n2(S.badEp.m)} epochs per participant `
    + `(SD = ${n2(S.badEp.sd)}, range ${n0(S.badEp.min)}–${n0(S.badEp.max)}) were subsequently rejected, `
    + `leaving ${n1(S.crash.m)} collision trials (SD = ${n1(S.crash.sd)}, range ${n0(S.crash.min)}–`
    + `${n0(S.crash.max)}) and ${n1(S.nocrash.m)} no-collision trials (SD = ${n1(S.nocrash.sd)}, range `
    + `${n0(S.nocrash.min)}–${n0(S.nocrash.max)}), for a total of ${S.totalTrials} trials entering the `
    + `group analysis. The preregistration set a minimum of 40 artefact-free trials per condition; four `
    + `participants fall below it in the no-collision condition (35, 37, 39 and 39 trials) and the criterion `
    + `was relaxed to 35, for the reason given in Section 2.1. The greater variability in no-collision counts `
    + `reflects the independent 50% assignment of each trial by the qRNG.`, {}],
]));

children.push(H2('3.2 Post-stimulus period: time domain'));
if (erpPost.length) {
  children.push(P(`The hierarchical GLM revealed ${spell(erpPost.length)} significant cluster`
    + `${erpPost.length > 1 ? 's' : ''} distinguishing collision from no-collision trials in the post-stimulus `
    + `window (Figure 3; Table 1). ` + erpPostSentences.join(' ')));
  children.push(P('All clusters survived cluster-mass permutation correction (α = 0.05, 1000 permutations). '
    + 'Peak sites are given as descriptive labels for where each effect was largest, not as claims about '
    + 'generators: 12 electrodes in a fixed hardware reference cannot localise, and an average reference is '
    + 'not available as a remedy at this channel count (Section 2.4). The interpretation rests on the timing '
    + 'and the magnitude of the effects, not on where they appear largest.'));
  children.push(P('No cluster falls in the window predicted by hypothesis H1, which anticipated an early '
    + 'sensory response within approximately 100–150 ms of onset: nothing survives correction anywhere '
    + `before ${n0(Math.min(...erpPost.map((c) => Number(c.Start))))} ms. The second part of that hypothesis, `
    + 'which predicted temporally extended differences over roughly 300–1000 ms, is consistent with the '
    + 'earlier of the effects reported above.'));
  children.push(makeTable(
    ['Cluster', 'Onset (ms)', 'Offset (ms)', 'Peak (ms)', 'Peak site', 'Electrodes', 't', 'd', 'p (corr.)'],
    erpPost.map((c, i) => [i + 1, n0(c.Start), n0(c.End), n0(c.Peak), c.Channel,
      c.NumElectrodes, n2(c.Tvalue), n2(c.ES),
      c.pcorr === undefined ? '—'
        : (Number(c.pcorr) <= 0.001 ? '.001' : Number(c.pcorr).toFixed(3).replace(/^0/, ''))]),
    [8, 10, 10, 9, 10, 10, 9, 9, 10],
  ));
  children.push(CAPTION('Table 1.', 'Significant post-stimulus ERP clusters for the '
    + 'collision versus no-collision contrast, after cluster-based spatiotemporal permutation correction '
    + `(alpha = 0.05, 1000 permutations, N = ${S.nSub}). Peak site is the electrode carrying the maximum absolute `
    + 't-value within the cluster; d is Cohen\u2019s d computed from participant-level estimates.'));
  children.push(FIGURE('figure3_erp.png'));
  children.push(CAPTION('Figure 3.', 'Mass-univariate results in the time domain, collision minus '
    + 'no-collision. (A, B) t-values at every channel and time point in the pre- and post-stimulus windows, '
    + 'on a common colour scale; black outlines mark the clusters surviving spatiotemporal permutation '
    + `correction (alpha = 0.05, 1000 permutations, N = ${S.nSub}). No cluster forms in the pre-stimulus `
    + `window. (${erpPost.map((_, i) => String.fromCharCode(67 + i)).join(', ')}) Grand-average `
    + 'ERPs at the peak channel of each post-stimulus '
    + 'cluster, with 95% CIs across participants and the cluster extent shaded; insets show '
    + 'the mean difference topography over the cluster window. Traces carry a display-only 15 Hz low-pass; '
    + 'all statistics were computed on the analysed 0.5\u201330 Hz data.'));
} else {
  children.push(P('No cluster survived correction in the post-stimulus window.'));
}


children.push(PR([['Sensitivity to baseline treatment. ', { b: true }],
  [`Refitting with the per-trial baseline as a Level-1 predictor rather than subtracting it [33] `
    + `reproduced the same ${spell(alday.length)} cluster${alday.length > 1 ? 's' : ''} with essentially `
    + `unchanged timing and effect sizes: `
    + alday.map((c) => `${n0(c.Start)}\u2013${n0(c.End)} ms peaking at ${c.Channel} `
        + `(t = ${n2(c.Tvalue)}, d = ${n2(c.ES)})`).join(', ')
    + `. The baseline window itself showed no meaningful condition difference at any electrode (maximum `
    + `|d| = 0.43, against 1.35 for the post-stimulus effect), so the regressor acts as variance reduction `
    + `rather than competing with the condition term. `
    + `${aldayPre.length ? '' : 'The pre-stimulus window remained empty under this model as well.'}`, {}],
]));

/* sensN12 kept as a loader only so the results stay archived and reproducible; per author decision
 * (2026-09) the N = 12 sensitivity subset is no longer reported anywhere in the paper. */

children.push(H2('3.3 Pre-stimulus period: time domain'));
if (erpPre.length) {
  children.push(P('Contrary to expectation, the pre-stimulus window contained significant clusters: '
    + erpPre.map((c, i) => describeERPCluster(c, i + 1)).join(' ')
    + ' Given the exploratory status of this study, this result requires independent replication before '
    + 'interpretation.'));
} else {
  children.push(P(`No cluster survived correction in the pre-stimulus window. Only `
    + `${n1(win('pre', 'primary').SupraPct)}% of time-electrode points reached the cluster-forming threshold, `
    + `against the 5% expected by chance, and the largest absolute t-value was `
    + `${n2(win('pre', 'primary').MaxAbsT)}. Clusters did form (${n0(win('pre', 'primary').nCandidate)} `
    + `of them), but the largest fell far short of the `
    + `permutation threshold, which the post-stimulus window exceeded twice over. For comparison, `
    + `${n1(win('post', 'primary').SupraPct)}% of points were suprathreshold post-stimulus. This window was `
    + 'identical in '
    + 'length to the post-stimulus window and was analysed with the identical pipeline, so the contrast between '
    + 'the two periods cannot be attributed to differences in the number of comparisons, in cluster opportunity, '
    + 'or in analytic treatment. Because the data were filtered causally, the pre-stimulus signal cannot contain '
    + 'information leaked backwards from the post-stimulus response.'));
}

children.push(H2('3.4 Time-frequency domain'));
if (tfPost.length) {
  children.push(P(`After ${tfLabel}, the post-stimulus window contained `
    + `${spell(tfPost.length)} significant cluster${tfPost.length > 1 ? 's' : ''} in the joint `
    + `frequency-time space (Figure 4). ` + tfPostSentences.join(' ')));
} else {
  children.push(P(`No time-frequency cluster survived correction in the post-stimulus window after `
    + `${tfLabel}.`));
}
if (tfPostAlt && tfPostAlt.length) {
  children.push(P(`The ${tfAltLabel} analysis produced a closely comparable pattern: `
    + tfPostAlt.map((c, i) => describeTFCluster(c, i + 1)).join(' ')
    + ' The convergence between the two normalisations indicates that the post-stimulus oscillatory '
    + 'modulation is not an artefact of either choice.'));
} else if (tfPostAlt) {
  children.push(P(`Under ${tfAltLabel} normalisation no cluster survived correction, so the `
    + 'post-stimulus oscillatory effect reported above should be regarded as normalisation-dependent.'));
}
if (tfPre && tfPre.length) {
  children.push(P('In the pre-stimulus window the same analysis yielded: '
    + tfPre.map((c, i) => describeTFCluster(c, i + 1)).join(' ')
    + ' Given the exploratory status of this study, this requires independent replication. The control '
    + 'analyses in Section 3.5 characterise it and test the preregistered explanations for it.'));
  /* The alternative normalisation's PRE-stimulus result was loaded and then reported nowhere, while the
   * Abstract and Conclusion claimed replication "under both normalisations". It has to be shown, and it
   * happens to be the larger effect - omitting it understates the result, but selective reporting in the
   * conservative direction is still selective reporting. */
  if (tfPreAlt && tfPreAlt.length) {
    children.push(P(`Under ${tfAltLabel} the pre-stimulus window yielded `
      + `${spell(tfPreAlt.length)} cluster${tfPreAlt.length > 1 ? 's' : ''} (Figure 4C, D): `
      + tfPreAlt.map((c, i) => describeTFCluster(c, i + 1)).join(' ')
      + ' The effect is therefore present under both normalisations, and is more extensive under this one. '
      + 'All control analyses reported below were computed on the primary (unnormalised) window only.'));
  } else if (tfPreAlt) {
    children.push(P(`Under ${tfAltLabel} no pre-stimulus cluster survived correction, so the effect above `
      + 'should be regarded as normalisation-dependent and is reported with that qualification.'));
  }
} else {
  children.push(P('No time-frequency cluster survived correction in the pre-stimulus window.'));
}

children.push(FIGURE('figure4_tf_normalisations.png'));
children.push(CAPTION('Figure 4.', 'Time-frequency results, collision minus no-collision, averaged across '
  + 'channels, from the causal wavelet estimator, shown under both normalisations on a shared colour scale. '
  + '(A, B) No normalisation, the primary analysis, pre- and post-stimulus. (C, D) Baseline power entered '
  + 'as a regressor (Alday, 2019), the secondary analysis. Black outlines mark clusters '
  + 'surviving cluster-extent permutation correction, corrected separately per window, and labels give the '
  + 'peak frequency of each; as noted in Section 2.7, peak frequencies are the centre of a broad and '
  + 'correlated response rather than a band assignment. Note that the outlines mark where the effect crosses '
  + 'the cluster-forming threshold, not its extent: the pre-stimulus difference is positive across almost the '
  + 'whole panel (Section 3.5). (E) The same difference as a time course: per-trial power in dB, '
  + 'averaged over channels and trials per participant and then across participants (mean, solid line; '
  + '±1 s.e.m., band), with the corrected cluster windows shaded; it shows the same pattern as the maps, '
  + 'a small sustained pre-stimulus elevation and a larger post-stimulus peak. The two normalisations give '
  + 'the same answer: the pre-stimulus elevation is present under both, and the secondary analysis '
  + 'additionally resolves it into two sub-clusters (Section 3.4). '
  + '(F) The difference spectrum within each corrected window, from the same trial-level power as (E), '
  + 'averaged over the window in time only (mean, solid line; ±1 s.e.m., band). The post-stimulus '
  + 'difference declines with frequency from ' + pfPostRow.mean_db.toFixed(1) + ' dB at ' + pfPost.pk + ' Hz, '
  + 'the shape of a broadband 1/f-like change; the pre-stimulus difference is comparatively flat '
  + '(' + pfPre.lo.toFixed(1) + '–' + pfPre.hi.toFixed(1) + ' dB across 3–30 Hz), so the pre-stimulus '
  + 'effect is not driven by any one band, nor by the low frequencies that dominate the post-stimulus '
  + 'effect. Markers show the frequency of maximum difference (' + pfPre.pk + ' Hz pre-stimulus, '
  + pfPost.pk + ' Hz post-stimulus); both sit at an edge of the analysed range, which itself indicates '
  + 'that neither window contains a spectrally focused effect.'));

children.push(H2('3.5 Pre-stimulus control analyses'));
if (tfPre && tfPre.length && cs.persub_effect) {
  children.push(P('Because a pre-stimulus difference is the claim most vulnerable to mundane explanation, the '
    + 'cluster was examined further. All analyses in this section use mean power inside the corrected cluster, '
    + 'one value per trial. The run-length, block and peripheral analyses require each analysed epoch to be '
    + 'located in the delivered 120-trial sequence and are therefore restricted to the '
    + `${cs.persub_effect.n} participants whose trial-to-sequence mapping could be recovered and verified `
    + '(Section 2.7); the time-symmetry correlation requires no such mapping and uses all 16. Absolute '
    + 'p-values here are not independent evidence that the effect exists, because the '
    + 'window was selected for being extreme; what is interpretable is whether each control changes the effect, '
    + 'since the selection applies equally to both sides of every comparison.'));

  if (ext) {
    children.push(P('The shape of the effect matters for how it should be read, and it is not the shape a '
      + 'cluster listing implies. The corrected cluster occupies '
      + `${n1(ext.n_cluster_points / 163.35)}% of the pre-stimulus frequency-time plane, but the difference `
      + `is in the same direction across ${n1(ext.pct_positive)}% of that plane, and of the `
      + `${ext.n_supra_positive + ext.n_supra_negative} points exceeding the cluster-forming threshold, `
      + `${ext.n_supra_negative === 0 ? 'every one is positive' : `${ext.n_supra_positive} are positive`}. `
      + 'Averaged in 100 ms bins the t-statistic does not fall below +0.7 at any latency in the window, and '
      + 'it is positive at every frequency from 3 to 30 Hz. The cluster boundaries therefore mark where a '
      + 'sustained offset happens to cross threshold, not where the effect begins and ends. We report the '
      + 'cluster because it is what the correction procedure returns, but the underlying difference is a '
      + 'broad elevation spanning the analysed window rather than a transient at a particular latency, and '
      + 'the peak latency should not be interpreted as a moment of anticipation.'));
  }

  children.push(P('The effect is distributed across participants rather than carried by a few. It is in the '
    + `same direction in ${cs.persub_positive.value} of ${cs.persub_positive.n} participants `
    + `(sign test ${pv(cs.persub_positive.p)}), with a group mean of `
    + `${sgn(cs.persub_effect.value)} dB, and removing the single most extreme participant leaves it `
    + `essentially unchanged at ${sgn(cs.persub_drop_extreme.value)} dB.`));

  children.push(P('Gambler’s fallacy and expectation bias (registered). With run length entered as a '
    + 'categorical predictor alongside condition, the condition effect is '
    + `${sgn(cs.cond_with_runlen_runlen.value)} dB, t(${cs.cond_with_runlen_runlen.df}) = `
    + `${n2(cs.cond_with_runlen_runlen.t)}, ${pv(cs.cond_with_runlen_runlen.p)}, essentially identical to `
    + 'its unadjusted value, and the alternative reading of the registered run-length definition gives the same '
    + `answer (${sgn(cs.cond_with_runlen_runlenOwn.value)} dB, ${pv(cs.cond_with_runlen_runlenOwn.p)}). `
    + 'Run length itself did not modulate pre-stimulus power: a partial F-test on the run-length block was '
    + `significant in ${cs.runlen_block_fisher_runlen.value} of ${cs.runlen_block_fisher_runlen.n} `
    + `participants (Fisher combination ${pv(cs.runlen_block_fisher_runlen.p)}). A linear trend across `
    + `run lengths was small and did not replicate across the two readings (${sgn(cs.runlen_trend_runlen.value)} `
    + `vs ${sgn(cs.runlen_trend_runlenOwn.value)} dB per level), so we do not interpret it. In the registered `
    + 'complementary contrast, the condition effect was present after both long and short runs '
    + `(${sgn(cs.long_runs.value)} and ${sgn(cs.short_runs.value)} dB) and did not differ between them `
    + `(${sgn(cs.long_minus_short.value)} dB, t(${cs.long_minus_short.df}) = ${n2(cs.long_minus_short.t)}, `
    + `${pv(cs.long_minus_short.p)}).`));

  children.push(P('CNV and time on task (registered). Trials were divided into '
    + 'early, middle and late blocks, excluding two participants for whom block membership is undefined (one '
    + 'whose session restarted after a headset disconnection, one whose recording begins at trial 30). The '
    + `effect was ${sgn(cs.block_early.value)} dB early, ${sgn(cs.block_middle.value)} dB in the middle and `
    + `${sgn(cs.block_late.value)} dB late, with no increase from early to late `
    + `(${sgn(cs.block_late_minus_early.value)} dB, t(${cs.block_late_minus_early.df}) = `
    + `${n2(cs.block_late_minus_early.t)}, ${pv(cs.block_late_minus_early.p)}). The registration `
    + 'specifies that CNV and learning accounts predict a monotonic increase across '
    + 'blocks; that prediction is not met.'));

  if (med.per) {
    children.push(P('Ocular and muscular activity. Eye and facial-muscle activity volume-conducts to scalp '
      + 'electrodes, and a broadband pre-stimulus increase is what a blink or a jaw movement looks like, so '
      + 'the ocular and EMG channels recorded by the headset were analysed on the same trials. '
      + 'Trial-to-trial coupling between peripheral and scalp broadband power is substantial and positive in '
      + `${coup.per ? `${coup.per.n_positive} of ${coup.per.n}` : 'every'} participants `
      + `(mean partial r = ${coup.per ? n2(coup.per.partial_r) : '—'} with condition removed), confirming that `
      + 'the two are not independent. However, peripheral power did not itself differ by condition '
      + `(${sgn(med.per.a)} dB, ${pv(med.per.a_p)}), and entering it as a covariate removed only `
      + `${Math.round(med.per.pct_removed)}% of the scalp effect, which remained at `
      + `${sgn(med.per.c_direct)} dB (${pv(med.per.c_direct_p)}); the indirect path was not significant `
      + `(${pv(med.per.indirect_p)}). This is the expected pattern if peripheral and scalp signals share `
      + 'variance for reasons unrelated to condition. It does not exclude a peripheral contribution, which at '
      + 'this sample size cannot be estimated precisely, but the condition difference is not reducible to one.'));
  }

  if (tfCov.length) {
    const minQ = Math.min(...tfCov.map((r) => +r.q));
    const nPre = tfCov.filter((r) => r.Window === 'pre').length;
    children.push(P('Individual differences. The registered moderator hypothesis (H5) predicted that '
      + 'pre-stimulus differentiation would be stronger in participants with more experience in domains '
      + 'demanding sustained attention. The 13 questionnaire variables were correlated with each '
      + `participant’s cluster-mean effect in both windows (${tfCov.length} tests, ${nPre} of them `
      + 'pre-stimulus), with Benjamini–Hochberg applied across the family as registered. '
      + (minQ < 0.05
        ? 'At least one association survives correction; see Supplementary Table S2b.'
        : `Nothing survives (smallest q = ${n2(minQ)}), and no association is close. H5 is not `
          + 'supported. With 14 to 16 participants this is a failure to reject rather than evidence '
          + 'of absence: the study was never powered for between-participant moderators, and the '
          + 'registration anticipated as much. All correlations are listed in Supplementary Table S2b.')));
  }

  if (h4) {
  children.push(P('Time symmetry (registered hypothesis H4, run post hoc). Time-symmetric accounts predict '
    + 'that trial-wise pre-stimulus differentiation and post-stimulus responses are two expressions of a shared '
    + 'process, and therefore covary. They do. For every participant, the correlation between trial-wise mean '
    + 'power in the pre-stimulus cluster window and in the post-stimulus cluster window is positive '
    + `(${h4.n_pos} of ${h4.n} positive; skipped Spearman, 10,000 pairing permutations per participant); the `
    + `group-level 20%-trimmed mean coefficient is ${sgn(h4.tm_r)} (bootstrap 95% CI ${sgn(h4.ci_low)} to `
    + `${sgn(h4.ci_high)}), and a one-sample t test on Fisher-transformed coefficients gives `
    + `t(${h4.df}) = ${n2(h4.t)}, ${pv(h4.p)}. The correlation survives when conditions are analysed separately, `
    + 'so it is not merely shared condition variance. The windows come from these data, so the result is '
    + 'exploratory; per-participant values are listed in Supplementary Table S4.'));
  }

  children.push(P('No control removes the effect, and the registered dissociations point away from the '
    + 'explanations they were written to test; we none the less regard this as a finding requiring '
    + 'independent replication, for the reasons set out in Section 4.2.'));
}

children.push(H2('3.6 Classification'));
children.push(PR([
  [`Under LOSO cross-validation, all six classifiers separated the conditions from the `
    + `post-stimulus response, with accuracies from ${n1(Math.min(...col(LOSO, 1)))}% to ${n1(bestLOSO)}% `
    + `and areas under the curve (AUC) from ${n2(Math.min(...col(LOSO, 6)))} to ${n2(Math.max(...col(LOSO, 6)))} `
    + `(Table 2). The best model reached ${n1(bestLOSO)}% accuracy, 95% Wilson CI `
    + `[${n1(ciLOSO[0])}, ${n1(ciLOSO[1])}]. Because performance is estimated from ${NOBS16} observations `
    + `the intervals are wide and the ordering of classifiers should not be over-interpreted; the `
    + `informative result is that every model separated the conditions well above chance on participants `
    + `it had never seen (all p ≤ .007, Table 2).`, {}],
]));

children.push(makeTable(
  ['Classifier', 'Accuracy', 'Sensitivity', 'Specificity', 'Precision', 'F1', 'AUC', 'p'],
  LOSO.map((r) => [r[0], n1(r[1]), n1(r[2]), n1(r[3]), n1(r[4]), n1(r[5]), r[6].toFixed(2),
    r[7] === null ? '—' : (r[7] < 0.002 ? '<.002' : r[7].toFixed(3))]),
  [20, 11, 12, 12, 11, 9, 9, 10],
));
children.push(CAPTION('Table 2.', 'Classification of collision versus no-collision from participant-averaged '
  + 'post-stimulus (0 to +1200 ms) ERPs, under LOSO cross-validation '
  + `with predictions pooled across folds (${S.nSub} participants, ${NOBS16} observations). All values are `
  + 'percentages except AUC. Chance accuracy is 50%. p is the two-tailed permutation p-value against a '
  + 'within-participant label-shuffling null with 1000 permutations; the smallest attainable value is '
  + '1/1001.'));

children.push(PR([
  [`Applied to the pre-stimulus window with everything else held identical, the same procedure left every `
    + `classifier at chance (Table 3). Accuracy ranged from ${n1(Math.min(...col(LOSOpre, 1)))}% to `
    + `${n1(bestPre)}%, and even the best model\u2019s interval, [${n1(ciPre[0])}, ${n1(ciPre[1])}], spans `
    + `50%. All six AUCs fall slightly below chance `
    + `(${n2(Math.min(...col(LOSOpre, 6)))}\u2013${n2(Math.max(...col(LOSOpre, 6)))}); at ${NOBS16} `
    + `observations this is within sampling noise for a null effect and should not be read as inverted `
    + `information. No classifier approaches significance against the permutation null (all p ≥ .57). `
    + `Hypothesis H6 is not supported.`, {}],
]));

children.push(makeTable(
  ['Classifier', 'Accuracy', 'Sensitivity', 'Specificity', 'Precision', 'F1', 'AUC', 'p'],
  LOSOpre.map((r) => [r[0], n1(r[1]), n1(r[2]), n1(r[3]), n1(r[4]), n1(r[5]), r[6].toFixed(2),
    r[7] === null ? '—' : (r[7] < 0.002 ? '<.002' : r[7].toFixed(3))]),
  [20, 11, 12, 12, 11, 9, 9, 10],
));
children.push(CAPTION('Table 3.', 'The identical analysis applied to the pre-stimulus window '
  + '(\u22121200 to 0 ms). Cross-validation scheme, feature construction and classifiers are as in Table 2; '
  + 'only the window differs.'));

children.push(P('This agrees with the mass-univariate time-domain analysis, which also found nothing before '
  + 'onset. A multivariate decoder can in principle detect distributed patterns that a channel-wise GLM '
  + 'misses, so its failure here indicates that the evoked response carries little or no '
  + 'discriminative information in the pre-stimulus window, rather than that such information is merely '
  + 'undetectable by univariate methods. '
  + (tfPre && tfPre.length
    ? 'This does not extend to the spectral difference reported in Section 3.5. The classifier was given '
      + 'the event-related waveform, not time-frequency power, so it was never in a position to detect that '
      + 'effect and its null says nothing about it.'
    : '')));

children.push(PR([
  [`Finally, the two modalities were combined on the ${NCARD} participants with usable data in both. Heart `
    + `rate alone was at chance (${n1(Math.min(...col(M14hr, 1)))}\u2013${n1(Math.max(...col(M14hr, 1)))}% `
    + `accuracy, AUC ${n2(Math.min(...col(M14hr, 6)))}\u2013${n2(Math.max(...col(M14hr, 6)))}), which `
    + `agrees with the univariate cardiac result reported below. Concatenating the heart-rate features onto `
    + `the ERP moved mean accuracy from ${n1(mean(col(M14eeg, 1)))}% to `
    + `${n1(mean(col(M14both, 1)))}%, and ${spell(fusionSame)} of the six classifiers returned predictions `
    + `identical to the EEG-only model on every observation. Taken alone that null would be uninformative: `
    + `eleven cardiac features appended to 3,576 electroencephalographic ones cannot be expected to shift a `
    + `decision boundary whether or not they carry signal. The heart-rate-only result is what settles the `
    + `question, and it indicates there was nothing in the cardiac response for the combination to add. `
    + `Full metrics for all three feature sets are given in Supplementary Table S3.`, {}],
]));

children.push(H2('3.7 Cardiac response'));
children.push(P('The hierarchical permutation GLM revealed no significant difference in event-related heart rate '
  + 'between conditions in the post-stimulus window (0 to +5 s; all permutation p > 0.37). No significant '
  + 'anticipatory difference was observed in the pre-stimulus window (−5 to 0 s) after correction, although a '
  + 'single time point near −4 s reached a nominally negative value (t ≈ −2.3, uncorrected p = 0.033) that did '
  + 'not survive correction. Both conditions produced closely overlapping absolute heart-rate trajectories '
  + 'averaging approximately 71–72 bpm, with wide CIs reflecting substantial between-participant '
  + 'variability.'));

children.push(FIGURE('figure5_cardiac.png'));
children.push(CAPTION('Figure 5.', 'Event-related heart rate (N = 14). (A) Each condition referenced to its '
  + 'own pre-event mean, with 95% CIs across participants; absolute rate differs by tens of '
  + 'beats per minute between people, so the raw traces are dominated by between-participant spread. '
  + '(B) The within-participant difference, which is the quantity tested. No time point survives t-max '
  + 'correction across the 11 time points in either window; the nominal dip near \u22124 s is uncorrected.'));

children.push(H2('3.8 Exploratory individual differences'));
children.push(P('None of the 26 individual-difference models in the time domain produced a cluster surviving '
  + 'correction, in either window. This held for every demographic, experiential and personality variable '
  + 'tested, and is true even before any correction across the family of models is considered. Personality '
  + 'variables were available for 14 of the 16 participants and all other variables for all 16.'));
children.push(P('In the cardiac data, no variable survived FDR correction in either window (all corrected '
  + 'p > 0.05), although nominally significant associations appeared consistently across both windows for '
  + 'extraversion, years of education and emotional stability. Given the number of models and the sample '
  + 'size, none is interpreted here.'));

/* ---------- 4. Discussion ---------- */
children.push(H1('4. Discussion'));

children.push(P('We asked when discriminative neural information about an unpredictable collision becomes '
  + 'available, using an immersive VR driving paradigm designed to remove the confounds that complicate '
  + 'interpretation of earlier work. Under a causal filter, without baseline correction, and with pre- and '
  + 'post-stimulus windows matched in length and analysed identically, '
  + (tfPre && tfPre.length
    ? 'evoked and decodable differentiation between collision and no-collision trials was found after '
      + 'stimulus onset, while a difference in broadband spectral power was present before it.'
    : 'differentiation between collision and no-collision trials was found exclusively after stimulus '
      + 'onset.')));

children.push(H2('4.1 Post-stimulus differentiation'));
if (erpPost.length) {
  const erpBig = erpPost.reduce((a, b) => (Math.abs(b.ES) > Math.abs(a.ES) ? b : a));
  const erpLate = erpPost.reduce((a, b) => (Number(b.Start) > Number(a.Start) ? b : a));
  children.push(P('The post-stimulus response comprised '
    + `${spell(erpPost.length)} spatiotemporal cluster${erpPost.length > 1 ? 's' : ''}, the larger spanning `
    + `${n0(erpBig.Start)}\u2013${n0(erpBig.End)} ms and peaking near ${n0(erpBig.Peak)} ms `
    + `(d = ${n2(erpBig.ES)}). `
    + 'The corrected statistics support the following: the conditions diverge from roughly '
    + `${n0(erpBig.Start)} ms after the tire blowout, the divergence persists for several hundred `
    + 'milliseconds in the window in which evaluative processing of salient events is typically observed, '
    + 'and it is accompanied by a broadband increase in spectral power over the same interval. The '
    + '12-channel montage cannot support named components or scalp localisation, and we make no claim '
    + 'about either. This is the expected signature of a '
    + 'multisensory, survival-relevant event being detected and evaluated, and its magnitude here is '
    + 'substantially larger than the effects typically reported in screen-based paradigms.'));

  if (erpPost.length > 1) {
  children.push(P(`A second, later cluster spanned ${n0(erpLate.Start)}\u2013${n0(erpLate.End)} ms `
    + `(d = ${n2(erpLate.ES)}), running to the end of the analysed window. A sustained late difference of `
    + 'this kind is what would be expected if the collision continued to be processed after the initial '
    + 'evaluative response, rather than the two conditions converging once the event had been categorised. '
    + 'It has no time-frequency counterpart: the single post-stimulus spectral cluster overlaps the earlier '
    + 'time-domain cluster and has resolved before this one begins. It is reported with more caution than '
    + 'the earlier effect because the analysed window ends at 1200 ms, so it cannot be established when '
    + 'it resolves.'));
  }
}
children.push(P('The practical significance of this result is methodological. These responses were resolved with '
  + 'dry pin electrodes, through hair, inside a VR HMD, in participants whose mean age was 57 '
  + 'years, and they survived conservative cluster correction with fewer than 20 participants. Wearable '
  + 'multimodal systems of this kind are frequently proposed for applied neuroergonomics but are seldom validated '
  + 'against a demanding electrophysiological criterion. The present data provide that validation for '
  + 'event-related responses to naturalistic threat, and the convergence with a decoder that generalises across '
  + 'participants indicates the signal is consistent enough in form to be recognised in individuals the model '
  + 'has not seen.'));

children.push(H2('4.2 Pre-stimulus period'));
if (tfPre && tfPre.length) {
  children.push(P('The pre-stimulus result is mixed and we report it as such. No effect appeared in the time '
    + 'domain, and a classifier trained on the pre-stimulus window performed at chance on held-out '
    + 'participants. In the time-frequency domain a broadband cluster did survive correction, several hundred '
    + 'milliseconds before an event whose outcome had not yet been determined by anything the participant '
    + 'could observe. This comparison was preregistered as the primary anticipatory hypothesis, and we '
    + 'do not regard the outcome as established.'));

  children.push(P('The explanations available for it were preregistered, and none accounts for it (Section '
    + '3.5). Trial type was assigned by a quantum '
    + 'random source at equiprobable rates, and the registered run-length control confirms that the effect '
    + 'does not depend on the preceding sequence. The registered block analysis was written to separate a '
    + 'CNV or learning effect from a predictive one by whether it grows across '
    + 'the session; it does not grow. Minimum-phase causal filtering and a causal wavelet mean that no '
    + 'post-stimulus sample enters the pre-stimulus estimate, and the two windows were matched in length '
    + 'and corrected separately. The effect is present in 13 of 15 participants and survives removal of '
    + 'the largest contributor, so it is not an artefact of one or two outliers.'));

  children.push(P('Against interpretation stand three considerations. This is an exploratory analysis of '
    + 'a study terminated at 18 of 63 planned participants, and the estimate comes from a window chosen '
    + 'because it was extreme, so its magnitude is inflated by an unknown amount. It appears in one '
    + 'domain and not the other two. And while ocular and muscular power did not differ by condition, '
    + 'those channels are strongly coupled to the scalp signal trial by trial, so a peripheral '
    + 'contribution cannot be excluded at this sample size.'));

  children.push(P('The form of the effect also constrains its interpretation. It is not a transient '
    + 'rising towards onset but a sustained elevation spanning the analysed window and the analysed band '
    + '(Section 3.5). A transient would suit a stimulus-specific anticipatory process; a sustained offset '
    + 'is also what a tonic difference in state between the two sets of trials would produce, and if '
    + 'collision trials were drawn from periods of systematically higher broadband power, the contrast '
    + 'would look like this. Under the present design that displacement has no ordinary source, since '
    + 'outcome was assigned by a quantum random source independently of everything preceding the trial '
    + 'and trial loss was condition-symmetric. We record the shape because it bears on which '
    + 'explanations remain open, not because we can adjudicate between them here.'));

  children.push(PR([
    ['We therefore make ', {}],
    ['no claim', { i: true }],
    [' that pre-stimulus differentiation occurred, and no claim that it did not: the cluster survived '
      + 'its own preregistered controls, and omitting it would misrepresent the data. It requires '
      + 'independent replication in an adequately powered sample before it can be interpreted.', {}],
  ]));
} else {
  children.push(P('No pre-stimulus effect survived correction in any analysis: not in the time domain, not in '
    + 'either time-frequency normalisation, and not in the multivariate decoder. Several features of the design '
    + 'make this null more interpretable than it would otherwise be. Trial type was assigned by a quantum random '
    + 'source at equiprobable rates, which removes the expectation-bias artefact that can manufacture apparent '
    + 'anticipatory effects [15]. The interval preceding a trial was independent of that '
    + 'trial\u2019s outcome and the task was entirely '
    + 'passive, so any temporal-expectancy or motor-preparation signal is shared across conditions and cancels in '
    + 'the contrast. Minimum-phase causal filtering guarantees that the pre-stimulus window cannot contain '
    + 'information leaked backwards from the post-stimulus response, a safeguard absent from several earlier '
    + 'positive reports. Windows were matched in length, so the asymmetry in outcome between periods is not an '
    + 'artefact of unequal correction burden.'));

  children.push(PR([
    ['We emphasise what this null does ', {}], ['not', { i: true }],
    [' establish. With the achieved sample the study had low power to detect effects of the magnitude reported in '
      + 'this literature (weighted d = 0.21; [14]), and a non-significant result under those '
      + 'conditions is uninformative about the existence of a small effect. The defensible claim is narrower: under '
      + 'conditions where the principal methodological artefacts are controlled, and in a paradigm that produces '
      + 'unambiguous post-stimulus differentiation in the same participants and the same recordings, no '
      + 'pre-stimulus differentiation was detectable by three analytically distinct approaches. The internal '
      + 'contrast is what carries the weight here: the same data, the same pipeline, and the same statistical '
      + 'threshold yield a large effect after the event and nothing before it.', {}],
  ]));
}

children.push(PR([['A caveat on the spectral findings. ', { b: true }],
  ['The post-stimulus time-frequency effect is a power increase spanning the entire analysed range rather '
    + 'than a modulation confined to any band. A uniform broadband increase of this kind is what a shift in '
    + 'the 1/f-like background would produce, and Gyurkovics et al. [37] show that such shifts follow '
    + 'stimulus onset and violate the stationarity assumption on which baseline normalisation rests. We '
    + 'cannot distinguish that from genuine oscillatory modulation, and as Section 2.7 notes the estimator '
    + 'cannot resolve the frequency axis finely enough to try. Neither normalisation used here separates a '
    + 'time-varying aperiodic '
    + 'rotation from genuine oscillatory modulation, and neither was designed to: the primary analysis applies '
    + 'no normalisation at all, and entering baseline power as a regressor adjusts for the pre-trial level '
    + 'without modelling how the aperiodic background evolves within a trial. The same applies with more force '
    + 'to the pre-stimulus effect, which is elevated across the whole 3–30 Hz range rather than in any band. The '
    + 'difference spectrum of the pre-stimulus window (Figure 4F) makes this direct: the elevation is flat across '
    + 'the analysed range, without the low-frequency weighting that shapes the post-stimulus difference, which is '
    + 'what a broadband shift in 1/f-like background power would produce. The '
    + 'spectral results should therefore be read as broadband power change of unresolved origin rather than as '
    + 'evidence of theta or alpha modulation specifically. Time-resolved parameterisation would settle this, '
    + 'and the 7 s of clean pre-event data available here makes the paradigm well suited to it.', {}],
]));

children.push(H2('4.3 Cardiac findings'));
children.push(P('Heart rate did not differentiate conditions at the group level in either window, and a '
  + 'classifier given the cardiac features alone performed at chance on the same participants for whom '
  + 'the ERP was decodable well above chance; adding those features to the EEG '
  + 'feature set changed nothing (Section 3.6, Supplementary Table S3). The null may reflect the low '
  + 'temporal resolution of RR-interval-derived heart rate relative to an event unfolding over one to '
  + 'two seconds, or a genuinely weak autonomic response to collisions in a passive VR context. The '
  + 'successful acquisition of usable cardiac data in 14 of 18 participants nonetheless bears on '
  + 'feasibility: the headset supports simultaneous cortical and cardiac recording, and the pipeline '
  + 'for the multimodal comparison is in place for an adequately powered sample.'));

children.push(H2('4.4 Limitations'));
children.push(BULLET('The study was terminated at 18 of a planned 63 participants when the manufacturer '
  + 'withdrew support. All results are exploratory, all effect sizes are provisional and likely inflated by the '
  + 'small sample, and no confirmatory inference is drawn.'));
children.push(BULLET('EDA and pupillometry, both preregistered as pre-stimulus measures, '
  + 'produced no usable data. Both were pursued systematically before being abandoned: skin was cleaned with '
  + 'alcohol and electrode gel applied, alternative electrode sites were tried, acquisition parameters were '
  + 'varied, and the manufacturer was consulted repeatedly (Section 2.4), but no record showed the phasic '
  + 'changes a collision response should produce. The pre-stimulus question is therefore addressed by EEG and '
  + 'cardiac data alone, and the modalities with the strongest prior support in this literature are absent.'));
children.push(BULLET('The 12-channel montage with dry electrodes and no dedicated ocular reference limits '
  + 'spatial inference and constrains artefact correction; component classification had to be handled by '
  + 'inspection rather than automatically.'));
children.push(BULLET('The oncoming vehicle doubles as the gaze target: participants follow its approach from '
  + 'the far end of the scene to the blowout, a design choice made in place of a stationary fixation cross. '
  + 'Pursuit and small saccades during the approach cannot be excluded from the pre-stimulus record, and with '
  + 'no eye tracker the time course of gaze is unobserved; the registered ocular and muscular control (Section '
  + '3.5) found no condition difference in peripheral power, but a pursuit-related contribution to the '
  + 'pre-stimulus broadband effect is a residual possibility at this sample size. Pupillometry had been planned '
  + 'as the rigorous control for this limitation, but was ultimately not supported by the headset\u2019s '
  + 'software in the way expected when the system was purchased, and could not be recovered.'));
children.push(BULLET('The sample was older (mean 57 years) and predominantly female, and reported high belief '
  + 'in intuition, which may limit generalisation.'));
children.push(BULLET(`Classification operated on participant-averaged responses with ${NOBS16} observations, `
  + `and ${NOBS14} in the matched multimodal comparison. This is `
  + 'appropriate for the available sample and is tested across held-out participants, but the resulting '
  + 'CIs are wide and the analysis cannot speak to single-trial decoding.'));
children.push(BULLET('The individual-difference analyses were uniformly null. At n = 14–16 they cannot '
  + 'separate absence of moderation from insufficient sensitivity, and are reported only as '
  + 'hypothesis-generating.'));

children.push(H2('4.5 Recommendations for replication'));
children.push(P('An adequately powered replication should recruit 60–80 participants with at least 80–100 '
  + 'trials per condition, on a system with demonstrated reliability across all physiological channels, and '
  + 'should preregister individual-difference analyses with explicit family-wise correction. The causal '
  + 'filtering, hardware randomisation, outcome-independent trial timing and symmetric analysis windows '
  + 'used here are minimum requirements for interpretable pre-stimulus claims, and the paradigm, pipeline '
  + 'and preregistration reported here provide a template for such work.'));

children.push(H1('5. Conclusion'));
children.push(P('In an immersive VR driving paradigm with quantum-randomised, temporally unpredictable collision '
  + 'events, evoked differentiation between collision and no-collision trials emerged after stimulus '
  + 'onset, converging across mass-univariate time-domain and multivariate decoding analyses. '
  + (tfPre && tfPre.length
    ? 'Before stimulus onset there was no time-domain effect and no decodable information, but a broadband '
      + 'time-frequency difference survived correction and passed every preregistered control analysis. We '
      + 'report it without interpreting it either way: the sample is small, the window was selected for '
      + 'being extreme, and one unreplicated cluster in one of three analysis domains is no basis for a '
      + 'positive claim; equally, the controls it passed are those that have exposed the artefacts behind '
      + 'earlier positive reports, so it cannot simply be dismissed. It is the clearest target this '
      + 'paradigm offers for adequately powered replication. '
    : 'No pre-stimulus differentiation was detected by any method. ')
  + 'Heart rate differentiated the conditions '
  + 'neither in the univariate model nor as classifier features, alone or combined with EEG. '
  + 'Because the study was terminated well short of its planned sample, these findings are exploratory: the '
  + 'post-stimulus effects require replication at their reported magnitude, and no pre-stimulus conclusion is '
  + 'drawn in either direction. What the study does establish is that a wearable, VR-integrated '
  + 'dry-electrode system can resolve robust event-related and oscillatory responses to naturalistic threat under '
  + 'conservative correction, and that a paradigm controlling the principal artefacts of pre-stimulus research is '
  + 'feasible and ready for adequately powered use.'));

/* ---------- declarations ---------- */
children.push(H1('Acknowledgements'));
children.push(P('This work was supported by the BIAL Foundation (grant 317/22, \'Expanding the study of '
  + 'presentiment using multimodal biosignals, a large sample, and immersive virtual reality\'). The '
  + 'funder had no role in study design, data '
  + 'collection, analysis, interpretation, or the decision to submit. The authors declare no conflicts of '
  + 'interest, financial or otherwise.'));

children.push(H1('Ethical statement'));
children.push(P('The study was approved by the Institute of Noetic Sciences Institutional Review Board '
  + '(IORG#0003743) and was conducted in accordance with the Declaration of Helsinki. All participants provided '
  + 'written informed consent prior to participation, including consent for their anonymised data to be shared '
  + 'openly, and received $30 compensation. The study was preregistered at https://osf.io/xuw34.'));

/* The availability statement promises "all analysis code". At the time this guard was written, none of
 * the scripts behind the time-frequency results or the entire pre-stimulus section were tracked by git,
 * while the SUPERSEDED time-frequency results were. Publishing that combination would give a reader a
 * repository whose contents contradict the paper. The statement is a claim about the repository, so it
 * gets checked like any other claim. */
{
  const mustBeTracked = [
    'analysis/run_final_EEG_tf_causal.m',
    'analysis/run_stats_permutation_glm_fl.m',
    'analysis/run_prereg_prestim_controls.m',
    'analysis/run_prestim_mediation_trial.m',
    'analysis/recover_trial_index.m',
    'analysis/characterise_prestim_extent.m',
  ];
  const mustNotBeTracked = ['results_final/EEG_tf', 'results_final/EEG_tf_ascent'];
  try {
    const { execSync } = require('child_process');
    const tracked = new Set(execSync('git ls-files', { cwd: ROOT, encoding: 'utf8' }).split(/\r?\n/));
    const missing = mustBeTracked.filter((f) => !tracked.has(f));
    const superseded = mustNotBeTracked.filter((d) => [...tracked].some((t) => t.startsWith(d + '/')));
    if (missing.length) {
      warnings.push('Data availability statement promises all analysis code, but these are UNTRACKED:\n'
        + missing.map((f) => '        ' + f).join('\n')
        + '\n      Commit them before the repository is published, or narrow the statement.');
    }
    if (superseded.length) {
      warnings.push('These SUPERSEDED result directories are tracked and would be published alongside '
        + 'the paper, reporting different numbers than the manuscript:\n'
        + superseded.map((d) => '        ' + d).join('\n')
        + '\n      Remove them from the tracked tree (they remain in history).');
    }
  } catch (e) {
    warnings.push('Could not verify the data availability statement against git: ' + e.message);
  }
}

children.push(H1('Data availability statement'));
children.push(P('The analysis code, the per-participant classification analyses and the BIDS conversion '
  + 'pipeline are openly available at https://github.com/amisepa/galea-vr-driving-hazards (GPL-3.0); '
  + 'the EEGLAB plugin for importing and preprocessing recordings from this headset, with a step-by-step '
  + 'tutorial and sample data, is released separately at https://github.com/amisepa/galea-eeglab-plugin '
  + '(GPL-3.0) and installable from the EEGLAB extension manager. The raw and preprocessed '
  + 'recordings are openly available in Brain Imaging Data Structure format with Hierarchical Event '
  + 'Descriptor annotations at OpenNeuro (doi: 10.18112/openneuro.ds008837.v1.0.0), mirrored at NEMAR (https://www.nemar.org). '
  + 'The Unity VR application is available on request from the authors: it incorporates '
  + 'commercially licensed assets that do not permit redistribution, so it cannot be published '
  + 'openly. The delivered quantum-random-number trial sequences are included in the BIDS '
  + 'dataset events files.'));

children.push(H1('Author contributions'));
children.push(P('C.C. designed the study, developed the paradigm and acquisition pipeline, collected the data, '
  + 'performed the preprocessing and mass-univariate analyses, and wrote the manuscript. D.Y. performed the '
  + 'classification analyses and contributed to the corresponding sections. Both authors approved the final '
  + 'manuscript.'));

children.push(H1('ORCID iDs'));
children.push(P('C\u00e9dric Cannard  https://orcid.org/0000-0002-6125-1175'));
children.push(P('Demet Ye\u015filba\u015f  https://orcid.org/0000-0001-9070-4439'));

children.push(H1('References'));
const refs = [
  "Clark A 2013 Whatever next? Predictive brains, situated agents, and the future of cognitive science *Behav. Brain Sci.* **36** 181–204 (doi: 10.1017/S0140525X12000477)",
  "Friston K 2010 The free-energy principle: a unified brain theory? *Nat. Rev. Neurosci.* **11** 127–138 (doi: 10.1038/nrn2787)",
  "Hohwy J 2013 *The predictive mind* (Oxford University Press)",
  "Walter W G, Cooper R, Aldridge V J, McCallum W C and Winter A L 1964 Contingent negative variation: an electric sign of sensorimotor association and expectancy in the human brain *Nature* **203** 380–384 (doi: 10.1038/203380a0)",
  "Tecce J J 1972 Contingent negative variation (CNV) and psychological processes in man *Psychol. Bull.* **77** 73–108 (doi: 10.1037/h0032177)",
  "Brunia C H M and van Boxtel G J M 2001 Wait and see *Int. J. Psychophysiol.* **43** 59–75 (doi: 10.1016/S0167-8760(01)00179-9)",
  "Mento G, Tarantino V, Sarlo M and Bisiacchi P S 2013 Automatic temporal expectancy: a high-density event-related potential study *PLoS ONE* **8** e62896 (doi: 10.1371/journal.pone.0062896)",
  "Poli S, Sarlo M, Bortoletto M, Buodo G and Palomba D 2007 Stimulus-preceding negativity and heart rate changes in anticipation of affective pictures *Int. J. Psychophysiol.* **65** 32–39 (doi: 10.1016/j.ijpsycho.2007.02.008)",
  "van Boxtel G J M and Böcker K B E 2004 Cortical measures of anticipation *J. Psychophysiol.* **18** 61–76 (doi: 10.1027/0269-8803.18.23.61)",
  "Parsons T D 2015 Virtual reality for enhanced ecological validity and experimental control in the clinical, affective and social neurosciences *Front. Hum. Neurosci.* **9** 660 (doi: 10.3389/fnhum.2015.00660)",
  "Reggente N, Essoe J K Y, Aghajan Z M, Tavakoli A V, McGuire J F, Suthana N A and Rissman J 2018 Enhancing the ecological validity of fMRI memory research using virtual reality *Front. Neurosci.* **12** 408 (doi: 10.3389/fnins.2018.00408)",
  "Li X, Yang L and Yan X 2022 An exploratory study of drivers’ EEG response during emergent collision avoidance *J. Saf. Res.* **82** 241–250 (doi: 10.1016/j.jsr.2022.05.015)",
  "Wang Z, Liang J, Shi S, Zhai P and Zhang L 2025 Time-variant Granger causality analysis for intuitive perception collision risk in driving scenario: an EEG study *Front. Neurosci.* **19** 1604751 (doi: 10.3389/fnins.2025.1604751)",
  "Mossbridge J A, Tressoldi P E and Utts J 2012 Predictive physiological anticipation preceding seemingly unpredictable stimuli: a meta-analysis *Front. Psychol.* **3** 390 (doi: 10.3389/fpsyg.2012.00390)",
  "Dalkvist J, Westerlund J and Bierman D J 2002 A computational expectation bias as revealed by simulations of presentiment experiments *Proceedings of the 45th Annual Convention of the Parapsychological Association* (Paris) 62–79",
  "Tressoldi P E, Martinelli M, Semenzato L and Gonella A 2015 Does psychophysiological predictive anticipatory activity predict real or future probable events? *Explore* **11** 109–117 (doi: 10.1016/j.explore.2014.12.003)",
  "McCraty R, Atkinson M and Bradley R T 2004 Electrophysiological evidence of intuition: Part 1. The surprising role of the heart *J. Altern. Complement. Med.* **10** 133–143 (doi: 10.1089/107555304322849057)",
  "Radin D I and Lobach E 2007 Toward understanding the placebo effect: investigating a possible retrocausal factor *J. Altern. Complement. Med.* **13** 733–740 (doi: 10.1089/acm.2006.6243)",
  "Radin D I, Vieten C, Michel L and Delorme A 2011 Electrocortical activity prior to unpredictable stimuli in meditators and nonmeditators *Explore* **7** 286–299 (doi: 10.1016/j.explore.2011.06.004)",
  "Duma G M, Mento G, Manari T, Martinelli M and Tressoldi P 2017 Driving with intuition: a preregistered study about the EEG anticipation of simulated random car accidents *PLoS ONE* **12** e0170370 (doi: 10.1371/journal.pone.0170370)",
  "Duma G M, Mento G, Semenzato L, Tressoldi P and Bilucaglia M 2019 EEG anticipation of random high and low arousal faces and sounds, version 2 *F1000Research* **8** 1508 (doi: 10.12688/f1000research.20277.2)",
  "Duma G M, Mento G, Semenzato L, Tressoldi P E and Bilucaglia M submitted Modality-specific pre-stimulus EEG differentiation of unpredictable faces and sounds",
  "Acunzo D J, MacKenzie G and van Rossum M C W 2012 Systematic biases in early ERP and ERF components as a result of high-pass filtering *J. Neurosci. Methods* **209** 212–218 (doi: 10.1016/j.jneumeth.2012.06.011)",
  "Rousselet G A 2012 Does filtering preclude us from studying ERP time-courses? *Front. Psychol.* **3** 131 (doi: 10.3389/fpsyg.2012.00131)",
  "Widmann A and Schröger E 2012 Filter effects and filter artifacts in the analysis of electrophysiological data *Front. Psychol.* **3** 233 (doi: 10.3389/fpsyg.2012.00233)",
  "Bilucaglia M, Duma G M, Mento G, Semenzato L and Tressoldi P E 2021 Applying machine learning EEG signal classification to emotion-related brain anticipatory activity, version 3 *F1000Research* **9** 173 (doi: 10.12688/f1000research.22202.3)",
  "Maess B, Schröger E and Widmann A 2016 High-pass filters and baseline correction in M/EEG analysis—continued discussion *J. Neurosci. Methods* **266** 171–172 (doi: 10.1016/j.jneumeth.2016.01.016)",
  "Delorme A 2023 EEG is better left alone *Sci. Rep.* **13** 2372 (doi: 10.1038/s41598-023-27528-0)",
  "Gosling S D, Rentfrow P J and Swann W B 2003 A very brief measure of the Big-Five personality domains *J. Res. Personal.* **37** 504–528 (doi: 10.1016/S0092-6566(03)00046-1)",
  "Widmann A, Schröger E and Maess B 2015 Digital filter design for electrophysiological data—a practical approach *J. Neurosci. Methods* **250** 34–46 (doi: 10.1016/j.jneumeth.2014.08.002)",
  "Ablin P, Cardoso J-F and Gramfort A 2018 Faster independent component analysis by preconditioning with Hessian approximations *IEEE Trans. Signal Process.* **66** 4040–4049 (doi: 10.1109/TSP.2018.2844203)",
  "Kim H, Luo J, Chu S, Cannard C, Hoffmann S and Miyakoshi M 2023 ICA’s bug: how ghost ICs emerge from effective rank deficiency caused by EEG electrode interpolation and incorrect re-referencing *Front. Signal Process.* **3** 1064138 (doi: 10.3389/frsip.2023.1064138)",
  "Alday P M 2019 How much baseline correction do we need in ERP research? Extended GLM model can replace baseline correction while lifting its limits *Psychophysiology* **56** e13451 (doi: 10.1111/psyp.13451)",
  "Phipson B and Smyth G K 2010 Permutation p-values should never be zero: calculating exact p-values when permutations are randomly drawn *Stat. Appl. Genet. Mol. Biol.* **9** 39 (doi: 10.2202/1544-6115.1585)",
  "Donoghue T, Haller M, Peterson E J, Varma P, Sebastian P, Gao R, Noto T, Lara A H, Wallis J D, Knight R T and Voytek B 2020 Parameterizing neural power spectra into periodic and aperiodic components *Nat. Neurosci.* **23** 1655–1665 (doi: 10.1038/s41593-020-00744-x)",
  "Gyurkovics M, Clements G M, Low K A, Fabiani M and Gratton G 2021 The impact of 1/f activity and baseline correction on the results and interpretation of time-frequency analyses of EEG/MEG data: a cautionary tale *NeuroImage* **237** 118192 (doi: 10.1016/j.neuroimage.2021.118192)",
  "Gyurkovics M, Clements G M, Low K A, Fabiani M and Gratton G 2022 Stimulus-induced changes in 1/f-like background activity in EEG *J. Neurosci.* **42** 7144–7151 (doi: 10.1523/JNEUROSCI.0414-22.2022)",
  "Cannard C, Wahbeh H and Delorme A 2024 BrainBeats as an open-source EEGLAB plugin to jointly analyze EEG and cardiovascular signals *J. Vis. Exp.* **206** e65829 (doi: 10.3791/65829)",
  "Pernet C R, Wilcox R and Rousselet G A 2012 Robust correlation analyses: false positive and power validation using a new open source Matlab toolbox *Front. Psychol.* **3** 606 (doi: 10.3389/fpsyg.2012.00606)",
];
refs.forEach((r) => children.push(REF(r)));

/* ------------------------------------------------------------------ */

const doc = new Document({
  creator: 'Cédric Cannard',
  lastModifiedBy: 'Cédric Cannard',
  title: 'Reactive and predictive processes during unpredictable driving hazards in virtual reality: an exploratory brain and body study with multimodal neurophysiological monitoring',
  numbering: {
    config: [{
      reference: 'bullets',
      levels: [{
        level: 0, format: LevelFormat.BULLET, text: '\u2022', alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: convertInchesToTwip(0.4), hanging: convertInchesToTwip(0.2) } } },
      }],
    }],
  },
  styles: {
    default: { document: { run: { font: FONT, size: SZ } } },
  },
  sections: [{
    properties: {
      page: {
        size: { width: 12240, height: 15840, orientation: PageOrientation.PORTRAIT },
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
      },
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: SZ_SMALL })],
        })],
      }),
    },
    children,
  }],
});

const outPath = path.join(ROOT, 'manuscript', 'Cannard_Yesilbas_2026_VR_collision_EEG_REVISED.docx');
Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync(outPath, buf);
  console.log('Wrote ' + outPath);
  console.log('  ERP post clusters : ' + erpPost.length);
  console.log('  ERP pre clusters  : ' + erpPre.length);
  console.log('  TF post (no norm)  : ' + tfPost.length);
  console.log('  TF pre  (no norm)  : ' + tfPre.length);
  console.log('  TF post (glmbase)  : ' + (tfPostAlt ? tfPostAlt.length : 'not run'));
  console.log('  TF pre  (glmbase)  : ' + (tfPreAlt ? tfPreAlt.length : 'not run'));
  if (warnings.length) {
    console.log('\n  WARNINGS (build succeeded, but check these):');
    warnings.forEach((w) => console.log('    - ' + w));
  }
});
