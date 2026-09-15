%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

%% H4 (time-symmetry) on the TF data - registered style, TF-based
%
% The registered H4 (q17, "Time-symmetry analysis") is peak-matched: it needs
% trial-wise pre- and post-stimulus indices from the windows identified by the
% primary collision vs no-collision effects. The primary PRE-stimulus analysis
% produced no surviving ERP cluster, so the ERP version was declared "not
% performed". A pre-stimulus effect WAS found in the TF analysis (3-30 Hz,
% -641..-464 ms, d = 0.99), so - exactly as with the H3 block analysis - the
% indices are taken from the TF clusters instead. This substitution is
% declared in the OSF update alongside the H3 one.
%
% Registered recipe, mapped to the TF data:
%   - per trial: mean power within the PRE cluster window (3-30 Hz x
%     -641..-464 ms) and within the POST cluster window (3-30 Hz x
%     266..766 ms), in dB (the dependent variable of the TF GLM)
%   - robust correlation: skipped Spearman (Robust Correlation Toolbox,
%     github.com/CPernet/Robust-Correlations, cloned 2026-09-11)
%   - significance per participant: within-participant permutation of the
%     pre-post pairing, 10,000 permutations, two-tailed (as registered)
%   - group level: participant-level correlations tested against zero
%     (one-sample t on atanh(r), plus a robust 20% trimmed-mean check)
%
% Input : results_final/EEG_tf_causal/causal_power_cache.mat
%         (channel-averaged raw power per trial, primary "none" mode)
% Output: results_final/EEG_tf_causal/h4_tf_symmetry.csv (+ log)
%
% Cedric Cannard, September 2026

clear; clc;
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
RES = paths.res_tf_causal;
TOOLBOX_DIR = paths.robust_correlations;
addpath(TOOLBOX_DIR);
addpath(genpath(fullfile(TOOLBOX_DIR, 'LIBRA')));   % mcdcov used by bivariate_outliers
rehash;
addpath(fullfile(RES));                                           % (noop, keeps -batch quiet)
ck = @(msg) fprintf('[%s] %s\n', datestr(now,'HH:MM:SS'), msg);

NPERM = 10000;          % registered
SEED  = 20260911;       % fixed seed for permutation pairings (reproducible)
WIN = struct( ...
    'pre',  struct('t', [-641.129032258064 -463.709677419355]), ...
    'post', struct('t', [ 266.129032258064  766.129032258064]));  % ms, from TF_clusters_corr-2.csv
FREQ = [3 30];          % Hz, both clusters span the full analysed band

ck('loading power cache ...');
S = load(fullfile(RES, 'causal_power_cache.mat'));
nSub = numel(S.RAW_CRASH);
nFreq = size(S.RAW_CRASH{1}, 1);
foi = 3:0.5:30;         % manuscript 2.7: 3 to 30 Hz in 0.5 Hz steps
assert(nFreq == numel(foi), 'nFreq = %d does not match 3:0.5:30', nFreq);
fIdx = find(foi >= FREQ(1) & foi <= FREQ(2));
assert(isequal(fIdx, 1:nFreq), 'clusters must span the full band');
tIdxPre  = find(S.times_ref >= WIN.pre.t(1)  & S.times_ref <= WIN.pre.t(2));
tIdxPost = find(S.times_ref >= WIN.post.t(1) & S.times_ref <= WIN.post.t(2));
ck(sprintf('pre window: %d freq x %d time samples; post: %d x %d', ...
    numel(fIdx), numel(tIdxPre), numel(fIdx), numel(tIdxPost)));

%% ---------- per-trial indices ----------
out = cell(nSub, 1);
for s = 1:nSub
    C = S.RAW_CRASH{s};   N = S.RAW_NOCRASH{s};    % [nFreq x nTime x nTrials]
    preC  = squeeze(mean(10*log10(C(fIdx, tIdxPre,  :)), [1 2]));
    postC = squeeze(mean(10*log10(C(fIdx, tIdxPost, :)), [1 2]));
    preN  = squeeze(mean(10*log10(N(fIdx, tIdxPre,  :)), [1 2]));
    postN = squeeze(mean(10*log10(N(fIdx, tIdxPost, :)), [1 2]));
    out{s} = struct('pre', [preC; preN], 'post', [postC; postN], ...
                    'nC', numel(preC), 'nN', numel(preN));
end

%% ---------- registered analysis ----------
ck('robust (skipped Spearman) correlations + 10,000-permutation nulls ...');
rng(2026, 'twister');
T = nan(nSub, 6); labels = cell(nSub, 1);
for s = 1:nSub
    pre = out{s}.pre;  post = out{s}.post;  n = numel(pre);
    r = skipped_Spearman([pre(:) post(:)]);                % observed (n x 2 input)
    % pre-generated, seeded permutation pairings (reproducible; parfor-safe)
    rng(SEED + s, 'twister');
    idx_all = cell(1, NPERM);
    for p = 1:NPERM, idx_all{p} = randperm(n); end
    cnt = 0;                                               % parfor reduction
    parfor p = 1:NPERM
        rp = skipped_Spearman([pre(:) post(idx_all{p})]);  % break the pairing
        cnt = cnt + (abs(rp) >= abs(r));
    end
    p_perm = (cnt + 1) / (NPERM + 1);
    % descriptive: within-condition versions (condition pooled is primary)
    rC = skipped_Spearman([out{s}.pre(1:out{s}.nC) out{s}.post(1:out{s}.nC)]);
    rN = skipped_Spearman([out{s}.pre(out{s}.nC+1:end) out{s}.post(out{s}.nC+1:end)]);
    T(s, :) = [r, p_perm, n, out{s}.nC, out{s}.nN, nan];
    labels{s} = sprintf('sub-%03d', s);   % cache order == subject_list order
    ck(sprintf('  sub-%02d  n=%3d (%d/%d)  skipped r = %+.3f  p_perm = %.4f  (rC %+.2f, rN %+.2f)', ...
        s, n, out{s}.nC, out{s}.nN, r, p_perm, rC, rN));
end

%% ---------- group level ----------
z = atanh(T(:,1));
[~, pz, ~, sz] = ttest(z);                                  % matches in-house precedent
tm  = trimmean(T(:,1), 20);                                 % robust group location
ci  = bootci(5000, {@(x) trimmean(x,20) - tm, T(:,1)});     % trimmed-mean BCa-ish CI
ck(sprintf('\nGROUP: mean atanh(r) t(%d) = %.2f, p = %.5f | 20%%-trimmed mean r = %+.3f [%.3f, %.3f] | %d of %d positive', ...
    sz.df, sz.tstat, pz, tm, tm+ci(1), tm+ci(2), sum(T(:,1) > 0), nSub));

hdr = {'r_skipped','p_perm_10k','n_trials','n_collision','n_nocollision'};
writetable([table(string(labels), 'VariableNames', {'sub'}), ...
            array2table(T(:,1:5), 'VariableNames', hdr)], ...
    fullfile(RES, 'h4_tf_symmetry.csv'));
grp = table(string({'group_t_on_z';'group_trimmed_mean_r';'ci_low';'ci_high'}), ...
            [sz.tstat; tm; NaN; NaN], [pz; NaN; NaN; NaN], [sz.df; NaN; NaN; NaN], ...
            [NaN; NaN; tm + ci(1); tm + ci(2)], ...
            'VariableNames', {'stat','value','p','df','extra'});
writetable(grp, fullfile(RES, 'h4_tf_symmetry_group.csv'));
ck('wrote h4_tf_symmetry.csv + h4_tf_symmetry_group.csv');