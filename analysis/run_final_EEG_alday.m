%% Alday (2019) GLM baseline correction - ERP sensitivity analysis
%
% Instead of SUBTRACTING a baseline (which assumes a coefficient of exactly -1
% and injects baseline noise into every trial estimate), the per-trial baseline
% is mean-centred and entered as a THIRD column of the Level-1 design matrix.
% The condition coefficient then estimates the effect controlling for baseline,
% with the baseline weight estimated from the data.
%
%   Alday, P. M. (2019). How much baseline correction do we need in ERP
%   research? Extended GLM model can replace baseline correction while
%   lifting its limits. Psychophysiology, 56(12), e13451.
%
% BASELINE WINDOW: -3000 to -2000 ms, common to BOTH analysis windows.
% Justification (measured from the raw markers): the approach phase preceding
% every event lasts 7.09 s (minimum 6.35 s across all 1,952 trials), so this
% window always sits inside the current trial and never touches the previous
% trial's response. It also ends 800 ms before the pre-stimulus analysis window
% begins, so it never overlaps a tested window, and being identical for both
% windows it preserves the pre/post symmetry of the design.
%
% WHY PER-CHANNEL: baseline level is channel-specific, but the Level-1 design
% matrix is shared across channels. Each channel is therefore fitted with its
% own design. The RNG is re-seeded identically before every channel so that all
% channels see the SAME permutations - otherwise the spatial structure of the
% null would be destroyed and cluster correction would be anti-conservative.
% 'Parallel' is off for the same reason (parfor RNG is not reproducible).
%
% This is a SENSITIVITY analysis. The preregistered primary remains the
% no-baseline model in run_final_EEG_erp.m.
%
% Cedric Cannard, August 2026

clear; close all; clc
set(0, 'DefaultFigureVisible', 'off');

paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
data_path   = paths.data;
output_path = paths.res_alday;
if ~exist(output_path,'dir'), mkdir(output_path); end

addpath(paths.robust)
addpath(fullfile(paths.robust, 'functions'))
addpath(paths.eeglab)
eeglab nogui;

diary(fullfile(output_path,'alday_run.log')); diary on
ck = @(m) fprintf('[%s] %s\n', datestr(now,'HH:MM:SS'), m);

BASELINE_WIN = [-3000 -2000];
SEED  = 2026;
nPerm = 1000; alpha = 0.05; mcc_type = 2; merge_clust = 10;

%% ---------------- LOAD ----------------
subject_list = dir(data_path);
subject_list = subject_list(contains({subject_list.name}, 'sub-'));
for b = {'sub-000','sub-005','sub-009'}
    subject_list(strcmp({subject_list.name}, b{1})) = [];
end
nSub = numel(subject_list);

new_order = {'Fp1','Fp2','F1','F2','CZ','C3','C4','PZ','P3','P4','O1','O2'};
[CRASH_TRIALS, NOCRASH_TRIALS] = deal(cell(nSub,1));
for iSub = 1:nSub
    sf = fullfile(data_path, subject_list(iSub).name);
    d  = load(fullfile(sf,'ERP_EEG_new.mat'));
    if strcmpi(subject_list(iSub).name,'sub-011')
        d2 = load(fullfile(sf,'ERP_EEG2_new.mat'));
        assert(~isequal(d.crash.data, d2.crash.data), 'sub-011 not repaired');
        d.crash.data    = cat(3, d.crash.data,    d2.crash.data);
        d.no_crash.data = cat(3, d.no_crash.data, d2.no_crash.data);
    end
    [~, idx] = ismember(new_order, {d.chanlocs.labels});
    chanlocs = d.chanlocs(idx);
    CRASH_TRIALS{iSub}   = d.crash.data(idx,:,:);
    NOCRASH_TRIALS{iSub} = d.no_crash.data(idx,:,:);
end
times_all = d.crash.times;
nChan = numel(chanlocs);
ck(sprintf('loaded N = %d, %d channels', nSub, nChan));

%% ---------------- PER-TRIAL BASELINE ----------------
bl_idx = times_all >= BASELINE_WIN(1) & times_all <= BASELINE_WIN(2);
fprintf('Baseline window %g to %g ms (%d samples)\n', BASELINE_WIN, sum(bl_idx));

% [nChan x nTrials] per subject, mean-centred WITHIN subject and channel
BL_CRASH   = cell(nSub,1);
BL_NOCRASH = cell(nSub,1);
for iSub = 1:nSub
    bc = squeeze(mean(CRASH_TRIALS{iSub}(:,bl_idx,:), 2));    % [nChan x nTrials]
    bn = squeeze(mean(NOCRASH_TRIALS{iSub}(:,bl_idx,:), 2));
    mu = mean([bc bn], 2);                                    % centre per channel
    BL_CRASH{iSub}   = bc - mu;
    BL_NOCRASH{iSub} = bn - mu;
end

% Does the baseline period itself differ by condition? If not, the baseline
% regressor is pure variance reduction with no collinearity against condition.
bl_d = nan(nChan,1);
for c = 1:nChan
    per_sub = arrayfun(@(s) mean(BL_CRASH{s}(c,:)) - mean(BL_NOCRASH{s}(c,:)), 1:nSub);
    bl_d(c) = mean(per_sub) / std(per_sub);
end
fprintf('\nCondition difference IN THE BASELINE WINDOW (Cohen d per channel):\n');
for c = 1:nChan
    fprintf('  %-5s d = %+.3f\n', chanlocs(c).labels, bl_d(c));
end
fprintf('max |d| = %.3f  (small values => no collinearity concern)\n\n', max(abs(bl_d)));

%% ---------------- GLM PER WINDOW ----------------
windows = {'post', [0 1200]; 'pre', [-1200 -1]};

for iWin = 1:size(windows,1)
    win_label = windows{iWin,1};
    tlims     = windows{iWin,2};
    time_idx  = times_all >= tlims(1) & times_all <= tlims(2);
    time      = times_all(time_idx);
    nTime     = numel(time);

    out_path = fullfile(output_path, [win_label '-stim']);
    if ~exist(out_path,'dir'), mkdir(out_path); end
    ck(sprintf('===== %s-stimulus [%g %g] ms =====', win_label, tlims));

    nc = cellfun(@(x) size(x,3), CRASH_TRIALS);
    nn = cellfun(@(x) size(x,3), NOCRASH_TRIALS);
    subj_idx = [repelem(1:nSub, nc)'; repelem(1:nSub, nn)'];
    cond     = [ones(sum(nc),1); zeros(sum(nn),1)];

    bl_all = [cell2mat(cellfun(@(x) x, BL_CRASH',   'uni',0))'; ...
              cell2mat(cellfun(@(x) x, BL_NOCRASH', 'uni',0))'];   % [nTrials x nChan]

    tvals = nan(nChan,nTime); pvals = nan(nChan,nTime);
    tvals_H0 = nan(nChan,nTime,nPerm); pvals_H0 = nan(nChan,nTime,nPerm);

    for c = 1:nChan
        Yc = cat(3, ...
            cell2mat(reshape(cellfun(@(x) x(c,time_idx,:), CRASH_TRIALS,   'uni',0),1,1,[])), ...
            cell2mat(reshape(cellfun(@(x) x(c,time_idx,:), NOCRASH_TRIALS, 'uni',0),1,1,[])));

        X = [ones(numel(cond),1), cond, bl_all(:,c)];

        rng(SEED,'twister');   % identical permutations for every channel
        % Freedman-Lane. The design has a THIRD column (the per-trial
        % baseline), and the library routine permutes only column 2, leaving
        % that covariate bound to its original trials. That is not
        % exchangeable and inflates the statistic - measured at 19/20 label
        % shuffles producing a cluster on the time-frequency version of this
        % same design. See analysis/run_stats_permutation_glm_fl.m.
        [~, tv, tvH0, ~, pv, pvH0] = run_stats_permutation_glm_fl( ...
            Yc, X, cond, nSub, nPerm, 'Subjects', subj_idx, ...
            'Method','WLS', 'WeightType','Huber', 'CondCol', 2, 'Progress', false);

        tvals(c,:)      = tv;
        pvals(c,:)      = pv;
        tvals_H0(c,:,:) = tvH0;
        pvals_H0(c,:,:) = pvH0;
        fprintf('   channel %2d/%d (%s) done\n', c, nChan, chanlocs(c).labels);
    end

    % see compute_mcc_fast.m for why the library version is not used here
    mask = compute_mcc_fast(tvals, pvals, tvals_H0, pvals_H0, alpha, chanlocs, nSub);

    summary_tbl = table();
    if any(mask,'all')
        [~, summary_tbl] = pull_clusters(mask, tvals, time, chanlocs, ...
            'time','dpt',{nSub}, merge_clust, [], [], 'd');
        writetable(summary_tbl, fullfile(out_path,'MAIN_clusters.csv'));
        ck(sprintf('%s-stim: %d cluster(s)', win_label, height(summary_tbl)));
        disp(summary_tbl)
    else
        ck(sprintf('%s-stim: NO cluster survived correction', win_label));
    end

    save(fullfile(out_path,'MAIN_stats.mat'), ...
        'tvals','pvals','mask','time','chanlocs','summary_tbl','BASELINE_WIN','bl_d','-v7.3');
end

ck('ALDAY SENSITIVITY ANALYSIS COMPLETE');
diary off
