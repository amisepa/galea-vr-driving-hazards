%% Generate every manuscript figure from results_final and the per-subject exports.
%
% Nothing here re-runs an analysis. Masks, t-values and cluster tables are read
% from the files written by the run_final_* scripts, so a figure cannot drift
% from a reported statistic.
%
%   methods_erp_sub013.png   example participant ERP, for Figure 1 (Methods)
%   methods_hr_sub013.png    example participant heart rate, for Figure 1
%   figure3_erp.png          pre/post t-maps, cluster ERPs, difference topographies
%   figure4_tf_normalisations.png  time-frequency t-maps, both windows x both normalisations
%   figure5_cardiac.png      group heart rate, both conditions and the difference
%
% Figure 1 itself is a vector schematic, manuscript/figures/figure1_overview.svg;
% it embeds the two methods_*.png panels produced here.
%
% The Methods panels deliberately show ONE participant. Putting the group
% average in the Methods figure would pre-empt the group effect that Figure 2
% exists to report.
%
% Run after run_final_EEG_erp.m, run_final_EEG_tf_causal.m and export_for_ML.m.
% NOT run_final_EEG_tf.m - that is the superseded non-causal 1-15 Hz analysis and
% its output directory (results_final/EEG_tf) is no longer read by anything.
%
% Run on a normal MATLAB desktop; graphics hang in headless batch mode, so the
% figures cannot be regenerated from a terminal-only session. This is a real
% constraint, not a preference: a -batch run stalls indefinitely even with
% Visible 'off' and exportgraphics.
%
% Cedric Cannard, August 2026

clear; close all; clc

paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
EEGLAB_PATH = paths.eeglab;
ROOT        = paths.root;
RAW         = paths.data;
RES         = fullfile(ROOT, 'results_final');
FIG         = fullfile(ROOT, 'manuscript', 'figures');

EX_SUB     = 'sub-013';   % example participant shown in the Methods figure
EX_CHAN    = 'mean';      % 'mean' for the 12-channel average, or a label e.g. 'C3'
LP_DISPLAY = 15;          % Hz, display-only low-pass (analysed data are 0.5-30 Hz)

% The two Methods panels are exported with print(), not exportgraphics(), so the
% image is exactly the figure size and is NOT cropped to content. Both use the
% same horizontal axes rectangle, so with a symmetric time axis t = 0 always
% falls at AX_L + AX_W/2 = 0.55 of the image width. figure1_overview.svg
% relies on that constant to line the panels up with the blowout marker in
% panel A. Change AX_L or AX_W here and you must change it there too.
AX_L = 0.135; AX_W = 0.83;

if ~exist(FIG, 'dir'), mkdir(FIG); end
addpath(EEGLAB_PATH); eeglab nogui;

% palette, shared with figure1_overview.svg
CRASH = [178  58  46]/255;
NOCR  = [ 46 134 171]/255;
INK   = [ 38  49  59]/255;
MUT   = [104 115 126]/255;
PRECOL  = [243 239 214]/255;
POSTCOL = [221 234 242]/255;
DIFCOL  = [110  78 140]/255;

set(groot, 'defaultAxesFontName', 'Arial', 'defaultTextFontName', 'Arial', ...
           'defaultAxesFontSize', 8, 'defaultAxesXColor', INK, ...
           'defaultAxesYColor', INK, 'defaultAxesBox', 'off', ...
           'defaultFigureColor', 'w');

CMAP = rdbu(255);


%% ============ METHODS PANELS: one example participant ==================

D = load(fullfile(RAW, EX_SUB, 'ERP_EEG_new.mat'));
t = D.crash.times(:)';
srate = D.crash.srate;

cr = display_lowpass(D.crash.data,    srate, LP_DISPLAY);
nc = display_lowpass(D.no_crash.data, srate, LP_DISPLAY);

if strcmpi(EX_CHAN, 'mean')
    CR = squeeze(mean(cr, 1));  NC = squeeze(mean(nc, 1));
    chanTxt = 'average of 12 channels';
else
    ci = find(strcmpi({D.crash.chanlocs.labels}, EX_CHAN), 1);
    assert(~isempty(ci), 'channel %s not found', EX_CHAN);
    CR = squeeze(cr(ci,:,:)); NC = squeeze(nc(ci,:,:));
    chanTxt = EX_CHAN;
end

sel = t >= -1500 & t <= 1500;

f = newfig(3.6, 1.95);
ax = axes('Parent', f, 'Position', [AX_L 0.235 AX_W 0.70]); hold(ax, 'on');
h1 = ci_band(ax, t(sel), CR(sel,:)', CRASH);
h2 = ci_band(ax, t(sel), NC(sel,:)', NOCR);
patch_span(ax, [-1200 0],   PRECOL);
patch_span(ax, [0     1200], POSTCOL);
yline(ax, 0, 'Color', [0.79 0.82 0.85], 'LineWidth', 0.7);
xline(ax, 0, '--', 'Color', INK, 'LineWidth', 0.9);
xlim(ax, [-1500 1500]);
xlabel(ax, 'Time from tire blowout (ms)');
ylabel(ax, 'Amplitude (\muV)');
legend(ax, [h1 h2], {'collision', 'no-collision'}, 'Box', 'off', ...
       'FontSize', 7, 'Location', 'northwest');
yl = ylim(ax);
text(ax, -600, yl(2)*0.94, 'pre-stimulus',  'FontSize', 7, 'Color', MUT, 'HorizontalAlignment', 'center');
text(ax,  600, yl(2)*0.94, 'post-stimulus', 'FontSize', 7, 'Color', MUT, 'HorizontalAlignment', 'center');
print(f, fullfile(FIG, 'methods_erp_sub013.png'), '-dpng', '-r300');
close(f);
fprintf('methods_erp_sub013.png  %s, %s, %d vs %d trials\n', EX_SUB, chanTxt, ...
        size(CR,2), size(NC,2));

P = load(fullfile(RAW, EX_SUB, 'ERP_PPG.mat'));
th = double(P.time(:))';

f = newfig(3.6, 1.7);
ax = axes('Parent', f, 'Position', [AX_L 0.26 AX_W 0.68]); hold(ax, 'on');
h1 = ci_band(ax, th, P.crash',   CRASH, true);
h2 = ci_band(ax, th, P.nocrash', NOCR,  true);
patch_span(ax, [0 max(th)], POSTCOL);
xline(ax, 0, '--', 'Color', INK, 'LineWidth', 0.9);
xlim(ax, [min(th) max(th)]);
xlabel(ax, 'Time from tire blowout (s)');
ylabel(ax, 'Heart rate (bpm)');
legend(ax, [h1 h2], {'collision', 'no-collision'}, 'Box', 'off', ...
       'FontSize', 7, 'Location', 'northwest');
print(f, fullfile(FIG, 'methods_hr_sub013.png'), '-dpng', '-r300');
close(f);
fprintf('methods_hr_sub013.png   %s, %d vs %d trials\n', EX_SUB, ...
        size(P.crash,2), size(P.nocrash,2));


%% ============ FIGURE 2: mass-univariate time domain ====================

% 'primary' is standard adjacency clustering; sens_n12 is the minimum-trial
% sensitivity analysis. See analysis/rerun_final_stats.m.
POST = load(fullfile(RES, 'EEG_time', 'post-stim', 'primary', 'MAIN_stats.mat'));
PRE  = load(fullfile(RES, 'EEG_time', 'pre-stim',  'primary', 'MAIN_stats.mat'));
CL   = readtable(fullfile(RES, 'EEG_time', 'post-stim', 'primary', 'MAIN_clusters.csv'));
labels = {POST.chanlocs.labels};
chanOf = @(k) char(string(CL.Channel(k)));   % readtable gives cellstr or string
nChan  = numel(labels);
vlim   = ceil(max(max(abs(POST.tvals(:))), max(abs(PRE.tvals(:)))));

M = load(fullfile(ROOT, 'data', 'galea_ML_dataset.mat'));
et = M.ERP_times(:)';
erp_raw = M.ERP_avg;                                  % [nSub x 2 x nChan x nTime]
erp_s   = zeros(size(erp_raw));
for s = 1:size(erp_raw,1)
    erp_s(s,1,:,:) = display_lowpass(squeeze(erp_raw(s,1,:,:)), 1000/mean(diff(et)), LP_DISPLAY);
    erp_s(s,2,:,:) = display_lowpass(squeeze(erp_raw(s,2,:,:)), 1000/mean(diff(et)), LP_DISPLAY);
end

f = newfig(7.2, 5.2);

axA = axes('Parent', f, 'Position', [0.075 0.605 0.245 0.305]);
tmap(axA, PRE, labels, vlim, CMAP, 'Pre-stimulus: no cluster survives correction');
panel_letter(axA, 'A');

axB = axes('Parent', f, 'Position', [0.400 0.605 0.520 0.305]);
tmap(axB, POST, labels, vlim, CMAP, sprintf('Post-stimulus: %s corrected cluster%s', ...
    numword(height(CL)), plural(height(CL))));
panel_letter(axB, 'B');
for k = 1:height(CL)
    ci = find(strcmpi(labels, chanOf(k)), 1);
    text(axB, mean([CL.Start(k) CL.End(k)]), ci + 0.62, chanOf(k), ...
         'FontSize', 7, 'FontWeight', 'bold', 'Color', 'k', ...
         'HorizontalAlignment', 'center', 'BackgroundColor', 'w', 'Margin', 0.5);
end
cb = colorbar(axB, 'Position', [0.930 0.605 0.014 0.305]);
cb.Label.String = 't (collision - no-collision)';
cb.Label.FontSize = 7;
cb.FontSize = 6.5;

% shared y-scale across the three trace panels, with headroom for the topography
tsel = et >= -200 & et <= 1200;
lo = inf; hi = -inf;
for k = 1:height(CL)
    ci = find(strcmpi(labels, chanOf(k)), 1);
    for c = 1:2
        d = squeeze(erp_s(:, c, ci, tsel));
        mu = mean(d, 1); se = std(d, 0, 1)/sqrt(size(d,1));
        lo = min(lo, min(mu - 1.96*se)); hi = max(hi, max(mu + 1.96*se));
    end
end
lo = lo*1.06; hi = hi + 0.62*(hi - lo);

nCl = height(CL);
gap = 0.055;
wpanel = (0.925 - 0.075 - gap*(nCl-1)) / nCl;
xs = 0.075 + (0:nCl-1) * (wpanel + gap);
for k = 1:nCl
    ci = find(strcmpi(labels, chanOf(k)), 1);
    ax = axes('Parent', f, 'Position', [xs(k) 0.085 wpanel 0.345]); hold(ax, 'on');
    h1 = ci_band(ax, et(tsel), squeeze(erp_s(:,1,ci,tsel)), CRASH);
    h2 = ci_band(ax, et(tsel), squeeze(erp_s(:,2,ci,tsel)), NOCR);
    xlim(ax, [-200 1200]); ylim(ax, [lo hi]);
    patch_span(ax, [CL.Start(k) CL.End(k)], [240 217 168]/255);
    yline(ax, 0, 'Color', [0.79 0.82 0.85], 'LineWidth', 0.7);
    xline(ax, 0, '--', 'Color', INK, 'LineWidth', 0.9);
    xlabel(ax, 'Time from tire blowout (ms)');
    if k == 1
        ylabel(ax, 'Amplitude (\muV)');
        legend(ax, [h1 h2], {'collision', 'no-collision'}, 'Box', 'off', ...
               'FontSize', 6.5, 'Location', 'southwest');
    else
        set(ax, 'YTickLabel', []);
    end
    title(ax, sprintf('%s  %d-%d ms   d = %.2f', chanOf(k), ...
          round(CL.Start(k)), round(CL.End(k)), CL.ES(k)), ...
          'FontSize', 8, 'Color', INK, 'FontWeight', 'normal');
    panel_letter(ax, char('C' + k - 1));   % C, D, E, ...

    % mean difference topography over the cluster window
    win  = et >= CL.Start(k) & et <= CL.End(k);
    diff = squeeze(mean(mean(erp_raw(:,1,:,win) - erp_raw(:,2,:,win), 4), 1));
    tv   = max(abs(diff));
    axi = axes('Parent', f, 'Position', [xs(k)+wpanel-0.095 0.315 0.090 0.105]);
    topoplot(diff, POST.chanlocs, 'maplimits', [-tv tv], 'electrodes', 'on', ...
             'style', 'map', 'shading', 'interp', 'conv', 'on', 'whitebk', 'on', ...
             'headrad', 0.5, 'emarker', {'.', 'k', 4, 1});
    colormap(axi, CMAP);
    text(axi, 0, -0.72, sprintf('%+.1f \\muV at %s', diff(ci), chanOf(k)), ...
         'FontSize', 5.8, 'Color', MUT, 'HorizontalAlignment', 'center');
end
apply_cmap(f, CMAP);
exportgraphics(f, fullfile(FIG, 'figure3_erp.png'), 'Resolution', 300);

fprintf('figure3_erp.png         %d post clusters, %d pre\n', height(CL), sum(PRE.mask(:)));


%% ============ FIGURE 3: time-frequency ================================
% Source is the CAUSAL pipeline with NO normalisation, matching Section 2.7.
% The retired 'aperiodic' mode is gone, and with it TF_topo.mat: panel C
% showed a scalp topography per cluster, which cannot be produced now and
% should not be. The statistics run on channel-averaged power, so a per-cluster
% topography was always descriptive; with 12 dry electrodes and no reference
% montage it is not interpretable, and the manuscript makes no topographic
% claim. Panels A and B are the figure.
TFDIR = fullfile(RES, 'EEG_tf_causal', 'none');
TFP = load(fullfile(TFDIR, 'post-stim', 'TF_stats_post.mat'));
TFR = load(fullfile(TFDIR, 'pre-stim',  'TF_stats_pre.mat'));
TFC = readtable(fullfile(TFDIR, 'post-stim', 'TF_clusters_corr-2.csv'));
TFCpre = readtable(fullfile(TFDIR, 'pre-stim', 'TF_clusters_corr-2.csv'));
vlimTF = ceil(max(max(abs(TFP.tvals(:))), max(abs(TFR.tvals(:)))));

f = newfig(7.2, 2.8);
titles = {clusterTitle('Pre-stimulus',  height(TFCpre)), ...
          clusterTitle('Post-stimulus', height(TFC))};
sets   = {TFR, TFP};
tabs   = {TFCpre, TFC};
posx   = [0.075 0.520];
for k = 1:2
    S = sets{k};
    ax = axes('Parent', f, 'Position', [posx(k) 0.20 0.375 0.66]); hold(ax, 'on');
    imagesc(ax, S.time, S.foi, S.tvals);
    if any(S.mask(:))
        contour(ax, S.time, S.foi, double(S.mask), [0.5 0.5], 'k', 'LineWidth', 1.1);
    end
    set(ax, 'YDir', 'normal', 'CLim', [-vlimTF vlimTF]);
    colormap(ax, CMAP);
    ticks = [4 8 12 20 30];
    ticks = ticks(ticks >= min(S.foi) & ticks <= max(S.foi));
    set(ax, 'YTick', ticks);
    axis(ax, 'tight');
    xlabel(ax, 'Time from tire blowout (ms)');
    if k == 1, ylabel(ax, 'Frequency (Hz)'); end
    title(ax, titles{k}, 'FontSize', 8.5, 'Color', INK, 'FontWeight', 'normal');
    panel_letter(ax, char('A' + k - 1));
    Tk = tabs{k};
    for j = 1:height(Tk)
        pf = Tk.PeakFreq_Hz(j);
        dy = 0.9; if pf >= 10, dy = -0.9; end
        text(ax, Tk.PeakTime_ms(j), pf+dy, sprintf('%.1f Hz', pf), ...
             'FontSize', 6.5, 'FontWeight', 'bold', 'Color', 'k', ...
             'HorizontalAlignment', 'center', 'BackgroundColor', 'w', 'Margin', 0.5);
    end
    if k == 2
        cb = colorbar(ax, 'Position', [0.905 0.20 0.016 0.66]);
        cb.Label.String = 't (collision - no-collision)';
        cb.Label.FontSize = 7; cb.FontSize = 6.5;
    end
end
apply_cmap(f, CMAP);
exportgraphics(f, fullfile(FIG, 'figure3_tf.png'), 'Resolution', 300);
close(f);
fprintf('figure3_tf.png          %d post clusters, %d pre clusters\n', ...
    height(TFC), height(TFCpre));


%% ============ FIGURE S1: the two normalisations, side by side =========
% Figure 3 shows the PRIMARY analysis only (no normalisation). The paper also
% reports a baseline-as-regressor variant, and a reader is entitled to see it
% rather than take the claim of convergence on trust. Four panels: both windows
% under both normalisations, on a shared colour scale so they are comparable by
% eye. Same colour scale is the point - rescaling each panel independently would
% make two different effects look identical.
NRM = {'none','No normalisation (primary)'; 'glmbaseline','Baseline as regressor (secondary)'};
WIN = {'pre-stim','TF_stats_pre.mat','Pre-stimulus'; 'post-stim','TF_stats_post.mat','Post-stimulus'};
Sall = cell(2,2); Call = cell(2,2); vmax = 0;
for r = 1:2
    for cix = 1:2
        d = fullfile(RES,'EEG_tf_causal',NRM{r,1},WIN{cix,1});
        Sall{r,cix} = load(fullfile(d, WIN{cix,2}));
        fcsv = fullfile(d,'TF_clusters_corr-2.csv');
        if isfile(fcsv), Call{r,cix} = readtable(fcsv); else, Call{r,cix} = table(); end
        vmax = max(vmax, max(abs(Sall{r,cix}.tvals(:))));
    end
end
vmax = ceil(vmax);

f = newfig(7.2, 5.0);
posx = [0.075 0.520]; posy = [0.56 0.09];
for r = 1:2
    for cix = 1:2
        S = Sall{r,cix};
        ax = axes('Parent', f, 'Position', [posx(cix) posy(r) 0.375 0.35]); hold(ax,'on');
        imagesc(ax, S.time, S.foi, S.tvals);
        if any(S.mask(:))
            contour(ax, S.time, S.foi, double(S.mask), [0.5 0.5], 'k', 'LineWidth', 1.1);
        end
        set(ax, 'YDir','normal', 'CLim', [-vmax vmax], 'YTick', [4 8 12 20 30]);
        colormap(ax, CMAP); axis(ax, 'tight');
        if r == 2, xlabel(ax, 'Time from tire blowout (ms)'); end
        if cix == 1, ylabel(ax, 'Frequency (Hz)'); end
        nCl = height(Call{r,cix});
        title(ax, sprintf('%s — %s', WIN{cix,3}, clusterTitleShort(nCl)), ...
              'FontSize', 8, 'Color', INK, 'FontWeight', 'normal');
        panel_letter(ax, char('A' + (r-1)*2 + cix - 1));
        if cix == 2
            cb = colorbar(ax, 'Position', [0.905 posy(r) 0.016 0.35]);
            cb.Label.String = 't (collision - no-collision)';
            cb.Label.FontSize = 7; cb.FontSize = 6.5;
        end
    end
end
axlbl = axes('Parent', f, 'Position', [0 0 1 1], 'Visible','off', 'XLim',[0 1], 'YLim',[0 1]);
text(axlbl, 0.075, 0.965, NRM{1,2}, 'FontSize', 9, 'Color', INK, 'FontWeight','bold');
text(axlbl, 0.075, 0.495, NRM{2,2}, 'FontSize', 9, 'Color', INK, 'FontWeight','bold');
apply_cmap(f, CMAP);
exportgraphics(f, fullfile(FIG, 'figure4_tf_normalisations.png'), 'Resolution', 300);
close(f);
fprintf('figure4_tf_normalisations.png   both windows x both normalisations\n');

%% ======== FIGURE 4 panel E: power time-course of the TF difference ========
% The TF maps show where; this shows the same contrast as a time-resolved
% curve, the time-domain view the TF analysis cannot give directly. Statistic
% matches the paper's GLM exactly: per-trial dB (normalize_tf 'none'),
% channel-averaged, mean over trials, broadband mean over the 3-30 Hz grid,
% collision minus no-collision. Group mean +- SEM across participants.
% Shaded windows are the corrected clusters (pre -641..-464 ms, post
% 266..766 ms); drawn for orientation, not as boundary claims (Section 3.5).
CACHE = load(fullfile(RES, 'EEG_tf_causal', 'causal_power_cache.mat'));
nSub  = numel(CACHE.RAW_CRASH);
tref  = CACHE.times_ref(:)';
ncom  = min([cellfun(@(x) size(x,2), CACHE.RAW_CRASH); ...
             cellfun(@(x) size(x,2), CACHE.RAW_NOCRASH)]);
ddE = nan(nSub, ncom);
for iS = 1:nSub
    dC = mean(10*log10(CACHE.RAW_CRASH{iS}(:,1:ncom,:)), 3);   % trials-mean dB
    dN = mean(10*log10(CACHE.RAW_NOCRASH{iS}(:,1:ncom,:)), 3);
    ddE(iS,:) = mean(dC, 1) - mean(dN, 1);                     % broadband dB diff
end
mE  = squeeze(mean(ddE, 1));
seE = squeeze(std(ddE, 0, 1) / sqrt(nSub));
tE  = tref(1:ncom);
winE = tE >= -1200 & tE <= 1200;

f = newfig(7.2, 2.4);
axE = axes('Parent', (f), 'Position', [0.085 0.24 0.83 0.66]); hold(axE, 'on');
fill(axE, [tE(winE), fliplr(tE(winE))], ...
     [mE(winE)+seE(winE), fliplr(mE(winE)-seE(winE))], [0.80 0.80 0.80], ...
     'EdgeColor', 'none');
plot(axE, tE(winE), mE(winE), '-', 'Color', [0.15 0.35 0.65], 'LineWidth', 1.3);
plot(axE, [-3000 3000], [0 0], 'k-', 'LineWidth', 0.5);
plot(axE, [0 0], [-2 3], 'k-', 'LineWidth', 0.5);
xlabel(axE, 'Time from tire blowout (ms)');
ylabel(axE, 'Power difference (dB), 3-30 Hz');
set(axE, 'YLim', [-2 3], 'XLim', [-1200 1200], 'FontSize', 8);
% Cluster-extent bands via the house helper (Painters-safe; pre-data patch()
% calls get dropped by the renderer). Tan matches the cluster-extent colour
% used for the ERP clusters in Figure 3.
patch_span(axE, [-641 -464], [240 217 168]/255);
patch_span(axE, [266 766], [240 217 168]/255);
title(axE, 'Broadband power difference across time (primary normalisation)', ...
      'FontSize', 8, 'Color', INK, 'FontWeight', 'normal');
% panel_letter() places labels at -0.16 axes-normalised x, which for this wide
% axes lands off the left edge of the figure; place the letter directly.
annotation(f, 'textbox', [0.012 0.855 0.04 0.05], 'String', 'E', ...
    'FontSize', 11, 'FontWeight', 'bold', 'Color', [38 49 59]/255, ...
    'EdgeColor', 'none');
apply_cmap(f, CMAP);
exportgraphics(f, fullfile(FIG, 'figure4_tf_panelE_tmp.png'), 'Resolution', 300);
close(f);
%% ======== FIGURE 4 panel F: window difference spectra (peak frequencies) ==
% The requested peak-frequency view, done defensibly: the same GLM contrast
% as a difference spectrum, computed separately inside each corrected cluster
% window (pre -641..-464 ms, post 266..766 ms). The cache holds trial-level
% power already channel-trimmed (20% trimmed mean) by the pipeline; the dB
% statistic matches the paper's GLM (per-trial dB, window mean). The "peak
% frequency" is the argmax of the group-mean difference spectrum per window,
% marked on the curve and written to figure4_panelF_spectra.csv for the
% manuscript builder. NOTE: because the difference is broadband and 1/f-like
% (Section 4.2 caveat), the argmax can sit at the edge of the analysed range;
% the panel shows that directly instead of hiding it.
foi = (3:0.5:30)';                        % pipeline frequency grid (asserted upstream)
winsF = {-641, -464; 266, 766};
wlabF = {'pre', 'post'};
dsF = nan(nSub, numel(foi), 2);
for iW = 1:2
    wE = tE >= winsF{iW,1} & tE <= winsF{iW,2};        % mask on trimmed times
    wFull = false(1, size(CACHE.RAW_CRASH{1}, 2));
    wFull(1:ncom) = wE;                                 % explicit full-length mask
    for iS = 1:nSub
        dC = squeeze(mean(10*log10(CACHE.RAW_CRASH{iS}(:, wFull, :)), 3));   % [nFreq x nWin]
        dN = squeeze(mean(10*log10(CACHE.RAW_NOCRASH{iS}(:, wFull, :)), 3));
        dsF(iS, :, iW) = mean(dC, 2) - mean(dN, 2);        % window mean of per-trial dB
    end
end
mF  = squeeze(mean(dsF, 1));                             % [nFreq x 2] group mean
seF = squeeze(std(dsF, 0, 1)) / sqrt(nSub);              % [nFreq x 2] s.e.m.
[~, iPkF] = max(mF);                                     % per-window argmax
pkF = foi(iPkF);
FID = fopen(fullfile(RES, 'EEG_tf_causal', 'figure4_panelF_spectra.csv'), 'w');
fprintf(FID, 'window,freq_hz,mean_db,sem_db\n');
for iW = 1:2
    for iFr = 1:numel(foi)
        fprintf(FID, '%s,%.1f,%.4f,%.4f\n', wlabF{iW}, foi(iFr), mF(iFr,iW), seF(iFr,iW));
    end
end
fclose(FID);

f = newfig(7.2, 2.2);
axF = axes('Parent', f, 'Position', [0.085 0.22 0.83 0.68]); hold(axF, 'on');
COLF = {[0.65 0.40 0.15], [0.15 0.35 0.65]};             % pre warm / post blue
BANDF = {[0.93 0.88 0.82], [0.85 0.89 0.94]};
for iW = 1:2
    fill(axF, [foi, fliplr(foi)], ...
         [mF(:,iW)+seF(:,iW), fliplr(mF(:,iW)-seF(:,iW))], BANDF{iW}, ...
         'EdgeColor', 'none');
end
plot(axF, [3 30], [0 0], 'k-', 'LineWidth', 0.5);
hFpre  = plot(axF, foi, mF(:,1), '-', 'Color', COLF{1}, 'LineWidth', 1.3);
hFpost = plot(axF, foi, mF(:,2), '-', 'Color', COLF{2}, 'LineWidth', 1.3);
yLoF = min(mF(:) - seF(:));  yHiF = max(mF(:) + seF(:));
padF = 0.18 * (yHiF - yLoF);
for iW = 1:2
    plot(axF, pkF(iW), mF(iPkF(iW), iW), 'v', 'MarkerSize', 7, ...
        'MarkerFaceColor', COLF{iW}, 'MarkerEdgeColor', 'k');
    % clamp the label inside the axes: edge-sitting peaks (3-4 Hz, 30 Hz)
    % would otherwise have their text half-cropped
    txF = min(max(pkF(iW), 4.6), 28.0);
    if pkF(iW) > 15, haF = 'right'; else, haF = 'left'; end
    text(axF, txF, mF(iPkF(iW), iW) + padF*0.55, sprintf('peak %g Hz', pkF(iW)), ...
        'FontSize', 7.5, 'HorizontalAlignment', haF, 'VerticalAlignment', 'bottom');
end
xlabel(axF, 'Frequency (Hz)');
ylabel(axF, 'Power difference (dB)');
set(axF, 'XLim', [3 30], 'XTick', 3:3:30, 'YLim', [yLoF-padF yHiF+padF], 'FontSize', 8);
legend(axF, [hFpre hFpost], {'pre-stimulus (-641..-464 ms)', 'post-stimulus (266..766 ms)'}, ...
    'Location', 'northeast', 'FontSize', 7);
title(axF, 'Difference spectrum within each corrected window (primary normalisation)', ...
    'FontSize', 8, 'Color', INK, 'FontWeight', 'normal');
annotation(f, 'textbox', [0.012 0.855 0.04 0.05], 'String', 'F', ...
    'FontSize', 11, 'FontWeight', 'bold', 'Color', [38 49 59]/255, ...
    'EdgeColor', 'none');
apply_cmap(f, CMAP);
exportgraphics(f, fullfile(FIG, 'figure4_tf_panelF_tmp.png'), 'Resolution', 300);
close(f);
% Stack the 4 TF maps, the time-course panel and the window spectra into the
% final figure file (all 7.2 in wide at 300 dpi; exportgraphics crops each to
% content, so each part is rescaled to the map width and centred).
IM1 = imread(fullfile(FIG, 'figure4_tf_normalisations.png'));
PARTS = {'figure4_tf_panelE_tmp.png', 'figure4_tf_panelF_tmp.png'};
IMAll = IM1;
for iP = 1:numel(PARTS)
    IMP = imread(fullfile(FIG, PARTS{iP}));
    if size(IMP, 2) ~= size(IMAll, 2)
        IMP = imresize(IMP, [NaN size(IMAll, 2)], 'lanczos3');
        canvas = ones(size(IMP, 1), size(IMAll, 2), size(IMP, 3), 'like', IMP);
        lo = 1 + floor((size(IMAll, 2) - size(IMP, 2)) / 2);
        canvas(:, lo:lo+size(IMP, 2)-1, :) = IMP;
        IMP = canvas;
    end
    IMAll = [IMAll; IMP];
end
imwrite(IMAll, fullfile(FIG, 'figure4_tf_normalisations.png'));
delete(fullfile(FIG, 'figure4_tf_panelE_tmp.png'));
delete(fullfile(FIG, 'figure4_tf_panelF_tmp.png'));
fprintf('figure4_tf_normalisations.png   panels A-F (maps + time-course + window spectra)\n');


%% ============ FIGURE 4: cardiac =======================================

hr  = M.HR_avg;                     % [nSub x 2 x nTime]
thg = double(M.HR_times(:))';
nhr = size(hr, 1);

% Absolute rate differs by tens of bpm between people, so a CI on the raw
% traces is dominated by between-participant spread. Referencing each
% participant to their own pre-event mean leaves the event-related change.
base = mean(hr(:,:,thg < 0), 3);
hrc  = hr - repmat(base, 1, 1, numel(thg));
dif  = squeeze(hr(:,1,:) - hr(:,2,:));

f = newfig(7.2, 2.6);

ax = axes('Parent', f, 'Position', [0.075 0.20 0.375 0.64]); hold(ax, 'on');
h1 = ci_band(ax, thg, squeeze(hrc(:,1,:)), CRASH, true);
h2 = ci_band(ax, thg, squeeze(hrc(:,2,:)), NOCR,  true);
xlim(ax, [min(thg) max(thg)]);
patch_span(ax, [0 max(thg)], POSTCOL);
yline(ax, 0, 'Color', [0.79 0.82 0.85], 'LineWidth', 0.8);
xline(ax, 0, '--', 'Color', INK, 'LineWidth', 0.9);
xlabel(ax, 'Time from tire blowout (s)');
ylabel(ax, '\Delta HR from pre-event mean (bpm)');
legend(ax, [h1 h2], {'collision', 'no-collision'}, 'Box', 'off', 'FontSize', 7, ...
       'Location', 'northwest');
title(ax, sprintf('Event-related heart rate, N = %d', nhr), 'FontSize', 8.5, ...
      'Color', INK, 'FontWeight', 'normal');
panel_letter(ax, 'A');

ax = axes('Parent', f, 'Position', [0.575 0.20 0.375 0.64]); hold(ax, 'on');
ci_band(ax, thg, dif, DIFCOL, true);
xlim(ax, [min(thg) max(thg)]);
patch_span(ax, [0 max(thg)], POSTCOL);
yline(ax, 0, 'Color', [0.53 0.58 0.63], 'LineWidth', 0.9);
xline(ax, 0, '--', 'Color', INK, 'LineWidth', 0.9);
xlabel(ax, 'Time from tire blowout (s)');
ylabel(ax, '\Delta HR (bpm)');
title(ax, 'Within-participant difference (collision - no-collision)', ...
      'FontSize', 8.5, 'Color', INK, 'FontWeight', 'normal');
panel_letter(ax, 'B');

exportgraphics(f, fullfile(FIG, 'figure5_cardiac.png'), 'Resolution', 300);
close(f);
fprintf('figure5_cardiac.png     N = %d\n', nhr);

fprintf('\nAll figures written to %s\n', FIG);


%% ============ helpers =================================================

function apply_cmap(f, cmap)
% EEGLAB's topoplot resets the colormap, so assert it on every axes at the very
% end rather than at creation time.
colormap(f, cmap);
for a = findall(f, 'Type', 'axes')'
    colormap(a, cmap);
end
end

function w = numword(k)
words = {'one','two','three','four','five','six','seven','eight','nine','ten'};
if k >= 1 && k <= numel(words), w = words{k}; else, w = num2str(k); end
end

function p = plural(k)
if k == 1, p = ''; else, p = 's'; end
end

function s = clusterTitleShort(n)
if n == 0
    s = 'no cluster';
else
    s = sprintf('%s cluster%s', numword(n), plural(n));
end
end

function s = clusterTitle(period, n)
% Panel titles must follow the data. Hard-coding "no cluster" for the
% pre-stimulus panel, as an earlier version did, silently mislabels the figure
% when a cluster appears.
if n == 0
    s = sprintf('%s: no cluster', period);
else
    s = sprintf('%s: %s corrected cluster%s', period, numword(n), plural(n));
end
end

function f = newfig(wIn, hIn)
f = figure('Units', 'inches', 'Position', [1 1 wIn hIn], 'Color', 'w', ...
           'Renderer', 'painters', 'Visible', 'off', ...
           'PaperPositionMode', 'auto');   % so print() honours the figure size
end

function panel_letter(ax, ch)
% 1.16 x axes height above the axes bottom is the house position, but on a tall
% panel that lands past the top edge of the figure and the letter is clipped.
% Clamp to just inside the figure so no layout can lose its label.
pos = get(ax, 'Position');
yN  = min(1.16, (0.985 - pos(2)) / pos(4));
text(ax, -0.16, yN, ch, 'Units', 'normalized', 'FontSize', 11, ...
     'FontWeight', 'bold', 'Color', [38 49 59]/255);
end

function patch_span(ax, xlims, col)
% Background band across the full current y-range. MATLAB patches DO expand the
% axis limits, unlike matplotlib's axvspan, so span exactly the limits already
% in force and restore them afterwards. Call this AFTER the data are plotted.
yl = ylim(ax);
h = patch(ax, [xlims(1) xlims(2) xlims(2) xlims(1)], [yl(1) yl(1) yl(2) yl(2)], col, ...
          'EdgeColor', 'none', 'FaceAlpha', 1, 'HandleVisibility', 'off');
uistack(h, 'bottom');
ylim(ax, yl);
end

function h = ci_band(ax, x, data, col, marker)
% data: [nObs x nTime]. Mean with a 95% CI band; returns the line handle.
if nargin < 5, marker = false; end
mu = mean(data, 1);
se = std(data, 0, 1) ./ sqrt(size(data, 1));
lo = mu - 1.96*se; hi = mu + 1.96*se;
fill(ax, [x fliplr(x)], [lo fliplr(hi)], col, 'FaceAlpha', 0.18, ...
     'EdgeColor', 'none', 'HandleVisibility', 'off');
if marker
    h = plot(ax, x, mu, '-o', 'Color', col, 'LineWidth', 1.5, 'MarkerSize', 3, ...
             'MarkerFaceColor', col);
else
    h = plot(ax, x, mu, 'Color', col, 'LineWidth', 1.4);
end
end

function tmap(ax, S, labels, vlim, cmap, ttl)
imagesc(ax, S.time, 1:numel(labels), S.tvals); hold(ax, 'on');
if any(S.mask(:))
    contour(ax, S.time, 1:numel(labels), double(S.mask), [0.5 0.5], 'k', 'LineWidth', 1.1);
end
set(ax, 'YDir', 'reverse', 'CLim', [-vlim vlim], 'YTick', 1:numel(labels), ...
    'YTickLabel', labels, 'FontSize', 6.5, 'Layer', 'top');
colormap(ax, cmap);
xlim(ax, [min(S.time) max(S.time)]); ylim(ax, [0.5 numel(labels)+0.5]);
xlabel(ax, 'Time from tire blowout (ms)', 'FontSize', 8);
title(ax, ttl, 'FontSize', 8.5, 'Color', [38 49 59]/255, 'FontWeight', 'normal');
end

function y = display_lowpass(x, srate, cutoff)
% Zero-phase FIR low-pass for display only, via EEGLAB so no Signal Processing
% Toolbox dependency. x is [chan x time] or [chan x time x trials].
sz = size(x);
EEG = eeg_emptyset;
EEG.data   = reshape(x, sz(1), sz(2), []);
EEG.srate  = srate;
EEG.nbchan = sz(1);
EEG.pnts   = sz(2);
EEG.trials = size(EEG.data, 3);
EEG.xmin   = 0;
EEG.xmax   = (sz(2)-1)/srate;
EEG.times  = (0:sz(2)-1)/srate*1000;
EEG = eeg_checkset(EEG);
evalc('EEG = pop_eegfiltnew(EEG, ''hicutoff'', cutoff, ''plotfreqz'', 0);');
y = reshape(EEG.data, sz);
end

function c = rdbu(n)
% ColorBrewer RdBu, reversed so blue is negative and red positive.
anchors = [ 5 48 97; 33 102 172; 67 147 195; 146 197 222; 209 229 240; ...
          247 247 247; 253 219 199; 244 165 130; 214 96 77; 178 24 43; 103 0 31]/255;
xi = linspace(1, size(anchors,1), n);
c  = interp1(1:size(anchors,1), anchors, xi);
end
