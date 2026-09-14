%% Re-run the time-domain group statistics with the consolidated correction
%
% Replaces run_final_EEG_erp.m + run_final_EEG_prestim.m +
% run_final_EEG_clusters_limo.m + run_final_EEG_clusters_both.m, which had
% drifted apart. See manuscript/stats_review_2026-08.md.
%
% What this produces, for the post-stimulus and pre-stimulus windows:
%
%   primary/      cluster_correct with minchan = 0, standard adjacency
%                 clustering. This is the reported analysis.
%                 No minimum-neighbour criterion (FieldTrip minnbchan) is
%                 applied: it has no principled setting on a 12-electrode
%                 montage where adjacent sites are centimetres apart.
%   sens_n12/     primary correction on the 12 participants who meet the
%                 preregistered 40-trial-per-condition minimum.
%
% Compute only, no figures: MATLAB graphics abort in a headless session.
% Figures come from analysis/make_figures.m afterwards.
%
% Cedric Cannard, August 2026

clear; clc
SEED = 2026;

paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
data_path   = paths.data;
output_path = paths.res_time;

addpath(paths.robust)
addpath(fullfile(paths.robust, 'functions'))
addpath(paths.eeglab)
addpath(paths.analysis)
evalc('eeglab nogui');

% ---------------- SUBJECTS ----------------
subject_list = dir(data_path);
subject_list = subject_list(contains({subject_list.name}, 'sub-'));
subject_list(strcmp({subject_list.name}, 'sub-000')) = [];   % pilot
subject_list(strcmp({subject_list.name}, 'sub-005')) = [];   % 27 trials/condition
subject_list(strcmp({subject_list.name}, 'sub-009')) = [];   % signal quality
nSub = numel(subject_list);
fprintf('N = %d participants\n', nSub);

new_order = {'Fp1','Fp2','F1','F2','CZ','C3','C4','PZ','P3','P4','O1','O2'};
[CRASH_TRIALS, NOCRASH_TRIALS] = deal(cell(nSub,1));

for iSub = 1:nSub
    subFolder = fullfile(data_path, subject_list(iSub).name);
    data = load(fullfile(subFolder, 'ERP_EEG_new.mat'));
    if strcmpi(subject_list(iSub).name, 'sub-011')
        data2 = load(fullfile(subFolder, 'ERP_EEG2_new.mat'));
        assert(~isequal(data.crash.data, data2.crash.data), ...
            'sub-011 files are identical - run fix_sub011_erp_export.m first!')
        data.crash.data    = cat(3, data.crash.data,    data2.crash.data);
        data.no_crash.data = cat(3, data.no_crash.data, data2.no_crash.data);
    end
    [~, idx] = ismember(new_order, {data.chanlocs.labels});
    chanlocs = data.chanlocs(idx);
    CRASH_TRIALS{iSub}   = data.crash.data(idx,:,:);
    NOCRASH_TRIALS{iSub} = data.no_crash.data(idx,:,:);
end
times_all = data.crash.times;

nCr   = cellfun(@(x) size(x,3), CRASH_TRIALS);
nNoCr = cellfun(@(x) size(x,3), NOCRASH_TRIALS);
meets40 = min(nCr, nNoCr) >= 40;
fprintf('Participants meeting the preregistered 40-trial minimum: %d of %d\n', ...
    sum(meets40), nSub);
fprintf('  below it: %s\n', strjoin(cellfun(@(s,a,b) sprintf('%s (%d/%d)', s, a, b), ...
    {subject_list(~meets40).name}, num2cell(nCr(~meets40))', num2cell(nNoCr(~meets40))', ...
    'uni', 0), ', '));

% neighbour matrix, once
params.method = 'triangulation';
[~, nbmat] = get_channelneighbors(chanlocs, params);
fprintf('Mean neighbours per channel: %.1f\n', mean(sum(logical(nbmat),2)));

% ---------------- SETTINGS ----------------
nPerm  = 1000;
alpha  = 0.05;
windows = { 'post', [0 1200]; 'pre', [-1200 -1] };

% name, minchan, participants to keep
variants = { ...
    'primary',        0, true(nSub,1); ...
    'sens_n12',       0, meets40 };

DIAG = table();

for iWin = 1:size(windows,1)
    win_label = windows{iWin,1};
    tlims     = windows{iWin,2};
    time_idx  = times_all >= tlims(1) & times_all <= tlims(2);
    time      = times_all(time_idx);

    for iVar = 1:size(variants,1)
        vname   = variants{iVar,1};
        minchan = variants{iVar,2};
        keep    = variants{iVar,3};
        nK      = sum(keep);

        fprintf('\n\n========== %s-stimulus [%g %g] ms | %s | minchan=%d | N=%d ==========\n', ...
            win_label, tlims(1), tlims(2), vname, minchan, nK);

        rng(SEED, 'twister');   % same permutation stream for every variant

        CR = CRASH_TRIALS(keep);  NC = NOCRASH_TRIALS(keep);
        Y_crash   = cell2mat(reshape(cellfun(@(x) x(:,time_idx,:), CR, 'uni',0), 1,1,[]));
        Y_nocrash = cell2mat(reshape(cellfun(@(x) x(:,time_idx,:), NC, 'uni',0), 1,1,[]));
        Y_all     = cat(3, Y_crash, Y_nocrash);

        nc = cellfun(@(x) size(x,3), CR);
        nn = cellfun(@(x) size(x,3), NC);
        subj_idx      = [repelem(1:nK, nc)'; repelem(1:nK, nn)'];
        condition_col = [ones(sum(nc),1); zeros(sum(nn),1)];
        X             = [ones(numel(condition_col),1), condition_col];
        fprintf('Trials: %d (%d collision / %d no-collision)\n', ...
            numel(condition_col), sum(nc), sum(nn));

        [~, tvals, tvals_H0, ~, pvals, pvals_H0] = run_stats_permutation_glm_hierarchical( ...
            Y_all, X, condition_col, nK, nPerm, 'Subjects', subj_idx, ...
            'Method', 'WLS', 'WeightType', 'Huber', 'Progress', false);

        o = struct('alpha', alpha, 'df', nK-1, 'neighbours', nbmat, 'minchan', minchan);
        [mask, pcorr, info] = cluster_correct(tvals, tvals_H0, o);

        fprintf('t threshold %.3f | null 95th pct %.1f | %d candidate clusters | %d survive\n', ...
            info.tcrit, info.max_th, info.nObserved, max(mask(:)));

        supra = 100 * mean(abs(tvals(:)) > info.tcrit);
        disp(sprintf('suprathreshold %.2f%% of %d points | max |t| %.3f', ...
            supra, numel(tvals), max(abs(tvals(:)))));
        DIAG = [DIAG; table(string(win_label), string(vname), nK, info.tcrit, supra, ...
            max(abs(tvals(:))), info.nObserved, info.max_th, max(mask(:)), ...
            'VariableNames', {'Window','Variant','N','tcrit','SupraPct','MaxAbsT', ...
                              'nCandidate','NullP95','nSurvive'})];
        summary_tbl = summarise(info, mask, tvals, time, chanlocs, nK);
        if ~isempty(summary_tbl), disp(summary_tbl), end

        out_path = fullfile(output_path, [win_label '-stim'], vname);
        if ~exist(out_path,'dir'), mkdir(out_path); end
        if ~isempty(summary_tbl)
            writetable(summary_tbl, fullfile(out_path, 'MAIN_clusters.csv'));
        end
        save(fullfile(out_path, 'MAIN_stats.mat'), 'tvals', 'pvals', 'mask', 'pcorr', ...
            'time', 'chanlocs', 'summary_tbl', 'info', 'nK', 'minchan', 'SEED', '-v7.3');
        save(fullfile(out_path, 'PERM_output.mat'), 'tvals', 'tvals_H0', 'pvals', ...
            'pvals_H0', 'time', 'chanlocs', '-v7.3');
    end
end

writetable(DIAG, fullfile(output_path, 'window_summary.csv'));
disp(DIAG)

fprintf('\n\nALL DONE\n');


% =====================================================================
function T = summarise(info, mask, tvals, time, chanlocs, nSub)
T = table();
if isempty(info.clusters), return, end
n = height(info.clusters);
[Cluster, Start, End, Peak, Tvalue, ES, NumElectrodes, Mass, pcorr] = deal(nan(n,1));
Channel = cell(n,1);
for r = 1:n
    sel = mask == info.clusters.Cluster(r);
    [~, cols] = find(sel);
    Cluster(r) = info.clusters.Cluster(r);
    Start(r)   = time(min(cols));
    End(r)     = time(max(cols));
    Peak(r)    = time(info.clusters.PeakTimeIdx(r));
    Tvalue(r)  = info.clusters.PeakT(r);
    ES(r)      = info.clusters.PeakT(r) / sqrt(nSub);   % Cohen's d_z
    NumElectrodes(r) = sum(any(sel,2));
    Channel{r} = chanlocs(info.clusters.PeakSpaceIdx(r)).labels;
    Mass(r)    = info.clusters.Mass(r);
    pcorr(r)   = info.clusters.pcorr(r);
end
T = table(Cluster, Start, End, Peak, Tvalue, ES, NumElectrodes, Channel, Mass, pcorr);
T = sortrows(T, 'Start');
end
