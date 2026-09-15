%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

%% Exploratory individual-difference (moderator) models - time domain
%
% Re-runs the 13 Level-2 covariate GLMs on the REPAIRED data, for both the
% post- and pre-stimulus windows, and writes one summary table listing which
% survived. These are MODERATORS (does the size of the condition effect vary
% with the person?), not mediators.
%
% NOTE ON MULTIPLICITY: 13 covariates x 2 windows = 26 models here, each
% cluster-corrected within itself. The registration specifies a Benjamini-
% Hochberg false discovery rate step across the family of moderators, which
% operates on the per-model cluster p-values. That step is NON-BINDING
% whenever no model yields a surviving cluster, which is the case here: BH is
% a step-up procedure whose adjusted p-values are never smaller than the raw
% ones, so a family with no rejection before correction cannot gain one after
% it. Everything this script produces is exploratory on grounds of power and
% belongs in supplementary material.
%
% Run after fix_sub011_erp_export.m. ~15-20 min.
%
% Cedric Cannard, August 2026

clear; close all; clc
rng(2026, 'twister')
set(0, 'DefaultFigureVisible', 'off');

paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
data_path   = paths.data;
output_path = paths.res_covariates;
if ~exist(output_path, 'dir'), mkdir(output_path); end

addpath(paths.robust)
addpath(fullfile(paths.robust, 'functions'))
addpath(paths.eeglab)
addpath(paths.analysis)   % cluster_correct
eeglab nogui;

diary(fullfile(output_path, 'covariates_run.log')); diary on
ck = @(msg) fprintf('[%s] %s\n', datestr(now,'HH:MM:SS'), msg);

%% ---------------- LOAD DATA ----------------
subject_list = dir(data_path);
subject_list = subject_list(contains({subject_list.name}, 'sub-'));
for bad = {'sub-000','sub-005','sub-009'}
    subject_list(strcmp({subject_list.name}, bad{1})) = [];
end
nSubAll = numel(subject_list);

new_order = {'Fp1','Fp2','F1','F2','CZ','C3','C4','PZ','P3','P4','O1','O2'};
[CRASH_TRIALS, NOCRASH_TRIALS] = deal(cell(nSubAll,1));
for iSub = 1:nSubAll
    subFolder = fullfile(data_path, subject_list(iSub).name);
    d = load(fullfile(subFolder, 'ERP_EEG_new.mat'));
    if strcmpi(subject_list(iSub).name, 'sub-011')
        d2 = load(fullfile(subFolder, 'ERP_EEG2_new.mat'));
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
ck(sprintf('loaded N = %d', nSubAll));

%% ---------------- QUESTIONNAIRE DATA ----------------
raw = readtable(paths.questionnaires, 'Sheet', 'IDs');
quest_ids = cellfun(@(x) lower(strrep(x,'_','-')), raw.RespondentID, 'uni', false);
match_idx = zeros(nSubAll,1);
for iSub = 1:nSubAll
    k = find(strcmp(quest_ids, subject_list(iSub).name));
    assert(~isempty(k), 'no questionnaire row for %s', subject_list(iSub).name);
    match_idx(iSub) = k(1);
end

likert = containers.Map( ...
    {'Strongly disagree','Disagree','Neither agree nor disagree','Agree','Strongly agree'}, ...
    {1,2,3,4,5});

col = @(pat) getcol(raw, match_idx, pat);

Q = table();
Q.age        = col('PleaseEnterYourAge');
sx           = col('SexAtBirth');
Q.sex        = double(strcmpi(sx, 'Female'));
Q.education  = col('YearsOfFormalEducation');
Q.driving    = col('AtDriving');
Q.sports     = col('InSports');
Q.videogames = col('PlayingVideoGames');
Q.meditation = col('OfMeditating');

it = col('DoYouBelieveInIntuition');
Q.intuition = nan(nSubAll,1);
Q.intuition(strcmpi(it,'Yes')) = 1;
Q.intuition(strcmpi(it,'No'))  = 0;
Q.intuition(contains(it,'know','IgnoreCase',true)) = 0.5;

% TIPI-10: positive item + (6 - reverse item), /2
tipi_cols = find(contains(raw.Properties.VariableNames, 'ISeeMyselfAs', 'IgnoreCase', true));
assert(numel(tipi_cols) == 10, 'expected 10 TIPI items, found %d', numel(tipi_cols));
B = nan(nSubAll,10);
for j = 1:10
    v = raw{match_idx, tipi_cols(j)};
    for i = 1:nSubAll
        if iscell(v) && ischar(v{i}) && likert.isKey(v{i}), B(i,j) = likert(v{i}); end
    end
end
Q.extraversion        = (B(:,1) + (6-B(:,2)))/2;
Q.agreeableness       = (B(:,3) + (6-B(:,4)))/2;
Q.conscientiousness   = (B(:,5) + (6-B(:,6)))/2;
Q.emotional_stability = (B(:,7) + (6-B(:,8)))/2;
Q.openness            = (B(:,9) + (6-B(:,10)))/2;

covariates = Q.Properties.VariableNames;
fprintf('\nCovariate availability (N = %d total):\n', nSubAll);
for c = covariates
    fprintf('  %-22s n = %2d\n', c{1}, sum(~isnan(Q.(c{1}))));
end

%% ---------------- RUN THE MODELS ----------------
nPerm = 1000; alpha = 0.05; mcc_type = 2; merge_clust = 10;
windows = {'post', [0 1200]; 'pre', [-1200 -1]};

rows = {};
for iWin = 1:size(windows,1)
    win_label = windows{iWin,1};
    tlims     = windows{iWin,2};
    time_idx  = times_all >= tlims(1) & times_all <= tlims(2);
    time      = times_all(time_idx);

    for iCov = 1:numel(covariates)
        cname = covariates{iCov};
        cvals = Q.(cname);
        keep  = ~isnan(cvals);
        nSub  = sum(keep);

        ck(sprintf('%s-stim | %s | n = %d', win_label, cname, nSub));

        C1 = CRASH_TRIALS(keep); C2 = NOCRASH_TRIALS(keep);
        cv = cvals(keep);

        Yc = cell2mat(reshape(cellfun(@(x) x(:,time_idx,:), C1, 'uni',0), 1,1,[]));
        Yn = cell2mat(reshape(cellfun(@(x) x(:,time_idx,:), C2, 'uni',0), 1,1,[]));
        Y  = cat(3, Yc, Yn);

        nc = cellfun(@(x) size(x,3), C1);
        nn = cellfun(@(x) size(x,3), C2);
        subj_idx = [repelem(1:nSub, nc)'; repelem(1:nSub, nn)'];
        cond     = [ones(sum(nc),1); zeros(sum(nn),1)];
        X        = [ones(numel(cond),1), cond];

        out_path = fullfile(output_path, [win_label '-stim'], cname);
        if ~exist(out_path,'dir'), mkdir(out_path); end

        try
            [~, tvals, tvals_H0, ~, pvals, pvals_H0] = ...
                run_stats_permutation_glm_hierarchical_cov(Y, X, cond, nSub, nPerm, ...
                'Subjects', subj_idx, 'Method', 'WLS', 'WeightType', 'Huber', ...
                'Covariate', cv, 'GroupSplit', 'none', 'Progress', false, 'Parallel', true);
        catch ME
            warning('FAILED %s / %s: %s', win_label, cname, ME.message);
            rows(end+1,:) = {win_label, cname, nSub, 0, NaN, NaN, NaN, 'FAILED'}; %#ok<*SAGROW>
            continue
        end

        % Predictor 2 = covariate slope (the moderator effect)
        % compute_mcc's cluster loop is O(nClusters x nElements) and stalls on
        % noise-like maps, which is what most covariate slope maps are.
        mask = compute_mcc_fast(tvals(:,:,2), pvals(:,:,2), ...
            squeeze(tvals_H0(:,:,2,:)), squeeze(pvals_H0(:,:,2,:)), alpha, chanlocs, nSub);

        if any(mask,'all')
            [~, tbl] = pull_clusters(mask, tvals(:,:,2), time, chanlocs, ...
                'time', 'dpt', {nSub}, merge_clust, [], [], 'r');
            writetable(tbl, fullfile(out_path, 'COV_clusters.csv'));
            for k = 1:height(tbl)
                rows(end+1,:) = {win_label, cname, nSub, height(tbl), ...
                    tbl.Start(k), tbl.End(k), tbl.ES(k), char(tbl.Channel(k))};
            end
            ck(sprintf('   -> %d cluster(s)', height(tbl)));
        else
            rows(end+1,:) = {win_label, cname, nSub, 0, NaN, NaN, NaN, ''};
        end
        save(fullfile(out_path,'COV_stats.mat'), 'tvals','pvals','mask','time','chanlocs','cv','-v7.3');
    end
end

%% ---------------- SUMMARY ----------------
S = cell2table(rows, 'VariableNames', ...
    {'Window','Covariate','n','nClusters','Start_ms','End_ms','EffectSize_r','PeakChannel'});
writetable(S, fullfile(output_path, 'covariate_summary.csv'));

fprintf('\n=============== SUMMARY ===============\n');
disp(S)
sig = S(S.nClusters > 0, :);
fprintf('\n%d of %d models produced a surviving cluster.\n', height(sig), height(S));
if ~isempty(sig)
    fprintf('NOTE: uncorrected across the family of %d models. Exploratory only.\n', height(S));
end
diary off


% getcol() lives in analysis/functions/.
