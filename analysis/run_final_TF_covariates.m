%% Individual-difference (moderator) models on the TIME-FREQUENCY effects
%
% WHY THIS EXISTS. analysis/run_final_EEG_covariates.m tests whether the 13
% questionnaire variables moderate the condition effect in the TIME DOMAIN, in
% both windows. That was the right analysis when the only surviving effects were
% time-domain ones. It no longer covers the question, because the pre-stimulus
% effect is in the time-frequency domain and has no time-domain counterpart: the
% registered moderator hypothesis (H5, "pre-stimulus differentiation will be
% stronger in participants with greater experience in domains demanding
% sustained attention and anticipation") was therefore never actually tested
% against the effect that exists.
%
% WHAT IT DOES. For each participant, the condition effect is summarised as mean
% power inside the corrected cluster - the same quantity the preregistered
% control analyses use - and correlated with each covariate across participants.
% Both windows are run, so the post-stimulus cluster gets the same treatment.
%
% WHY A CORRELATION AND NOT A LEVEL-2 GLM OVER THE WHOLE MAP. The time-domain
% script fits a covariate at every channel-time point and cluster-corrects the
% resulting map, which is the more powerful design when there is no a priori
% region. Here there is one: the cluster is already defined, and re-searching
% the whole frequency-time plane for a covariate effect would add a second
% selection step on top of the first. Reducing to one number per participant
% costs sensitivity but keeps the test interpretable.
%
% CIRCULARITY, STATED. The cluster was selected for having an extreme condition
% effect. That inflates the mean effect but does NOT bias a between-participant
% correlation, because the selection used the group-level statistic and is blind
% to how individuals rank on any questionnaire. The correlations are honest; the
% cluster mean they operate on is not an unbiased effect size.
%
% MULTIPLICITY. 13 covariates x 2 windows = 26 tests, Benjamini-Hochberg across
% all 26, as the registration specifies for the moderator family. Reported
% whether or not anything survives.
%
% Cedric Cannard, September 2026

clear; close all; clc
rng(2026,'twister')
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
RES  = paths.res_tf_causal;
OUT  = paths.res_covariates;
QFILE = paths.questionnaires;
data_path = paths.data;
EXCLUDE = {'sub-000','sub-005','sub-009'};

%% ---- per-participant cluster effect, both windows ------------------------
C = load(fullfile(RES,'causal_power_cache.mat'), 'RAW_CRASH','RAW_NOCRASH','times_ref');
S = load(fullfile(data_path,'sInfo.mat'));
names = arrayfun(@(s) sprintf('sub-%03d', s.subject), S.sInfo, 'UniformOutput', false);
subjOrder = unique([S.sInfo(~ismember(names, EXCLUDE)).subject]);   % cache cell order
nSub = numel(subjOrder);
fprintf('Participants in the power cache: %d\n', nSub);

WINS = {'pre','pre-stim','TF_stats_pre.mat'; 'post','post-stim','TF_stats_post.mat'};
EFF = nan(nSub, 2);
for w = 1:2
    M = load(fullfile(RES,'none',WINS{w,2},WINS{w,3}), 'mask','time');
    if ~any(M.mask(:))
        fprintf('%s-stimulus: no cluster, skipping\n', WINS{w,1}); continue
    end
    tsel = ismember(round(C.times_ref,3), round(M.time,3));
    assert(sum(tsel) == numel(M.time), '%s: cluster time axis does not align', WINS{w,1});
    box = logical(M.mask);
    for k = 1:nSub
        c  = 10*log10(C.RAW_CRASH{k}(:, tsel, :));
        nc = 10*log10(C.RAW_NOCRASH{k}(:, tsel, :));
        mc = mean(c,3); mn = mean(nc,3);
        EFF(k,w) = mean(mc(box)) - mean(mn(box));
    end
    fprintf('%s-stimulus cluster effect: %+.3f dB (SD %.3f)\n', ...
        WINS{w,1}, mean(EFF(:,w)), std(EFF(:,w)));
end

%% ---- questionnaire variables, built exactly as the time-domain script ----
raw = readtable(QFILE, 'Sheet', 'IDs');
quest_ids = cellfun(@(x) lower(strrep(x,'_','-')), raw.RespondentID, 'uni', false);
match_idx = zeros(nSub,1);
for k = 1:nSub
    nm = sprintf('sub-%03d', subjOrder(k));
    j = find(strcmp(quest_ids, nm));
    assert(~isempty(j), 'no questionnaire row for %s', nm);
    match_idx(k) = j(1);
end

likert = containers.Map( ...
    {'Strongly disagree','Disagree','Neither agree nor disagree','Agree','Strongly agree'}, ...
    {1,2,3,4,5});
col = @(pat) getcol(raw, match_idx, pat);

Q = table();
Q.age        = col('PleaseEnterYourAge');
sx           = col('SexAtBirth');
Q.sex        = double(strcmpi(sx,'Female'));
Q.education  = col('YearsOfFormalEducation');
Q.driving    = col('AtDriving');
Q.sports     = col('InSports');
Q.videogames = col('PlayingVideoGames');
Q.meditation = col('OfMeditating');
it = col('DoYouBelieveInIntuition');
Q.intuition = nan(nSub,1);
Q.intuition(strcmpi(it,'Yes')) = 1;
Q.intuition(strcmpi(it,'No'))  = 0;
Q.intuition(contains(it,'know','IgnoreCase',true)) = 0.5;

tipi_cols = find(contains(raw.Properties.VariableNames,'ISeeMyselfAs','IgnoreCase',true));
assert(numel(tipi_cols) == 10, 'expected 10 TIPI items, found %d', numel(tipi_cols));
B = nan(nSub,10);
for j = 1:10
    v = raw{match_idx, tipi_cols(j)};
    for i = 1:nSub
        if iscell(v) && ischar(v{i}) && likert.isKey(v{i}), B(i,j) = likert(v{i}); end
    end
end
Q.extraversion        = (B(:,1) + (6-B(:,2)))/2;
Q.agreeableness       = (B(:,3) + (6-B(:,4)))/2;
Q.conscientiousness   = (B(:,5) + (6-B(:,6)))/2;
Q.emotional_stability = (B(:,7) + (6-B(:,8)))/2;
Q.openness            = (B(:,9) + (6-B(:,10)))/2;
covs = Q.Properties.VariableNames;

%% ---- correlate ----------------------------------------------------------
rows = {};
for w = 1:2
    if all(isnan(EFF(:,w))), continue; end
    fprintf('\n===== %s-STIMULUS CLUSTER =====\n', upper(WINS{w,1}));
    fprintf('%-22s %4s %8s %8s %10s\n', 'covariate', 'n', 'r', 'p', 'rho');
    for c = covs
        v = Q.(c{1});
        ok = ~isnan(v) & ~isnan(EFF(:,w));
        if sum(ok) < 6, continue; end
        [r,p]   = corr(v(ok), EFF(ok,w));
        rho     = corr(v(ok), EFF(ok,w), 'type','Spearman');
        fprintf('%-22s %4d %8.3f %8.4f %10.3f\n', c{1}, sum(ok), r, p, rho);
        rows(end+1,:) = {WINS{w,1}, c{1}, sum(ok), r, p, rho}; %#ok<SAGROW>
    end
end

% Benjamini-Hochberg across the whole moderator family, as registered.
pv = cell2mat(rows(:,5)); m = numel(pv);
[ps, ord] = sort(pv,'ascend');
adj = min(flipud(cummin(flipud(m*ps./(1:m)'))), 1);
q = nan(m,1); q(ord) = adj;
for i = 1:m, rows{i,7} = q(i); end
fprintf('\nBenjamini-Hochberg across all %d moderator tests: smallest q = %.3f\n', m, min(q));
if min(q) < 0.05
    fprintf('SURVIVING:\n');
    for i = find(q < 0.05)'
        fprintf('  %s-stimulus / %s : r = %+.3f, q = %.3f\n', rows{i,1}, rows{i,2}, rows{i,4}, q(i));
    end
else
    fprintf('No moderator survives correction. This is a failure to reject at N = %d, not\n', nSub);
    fprintf('evidence that no association exists; the study is not powered for moderators.\n');
end

T = cell2table(rows, 'VariableNames', {'Window','Covariate','n','r','p','rho','q'});
writetable(T, fullfile(OUT,'tf_covariate_summary.csv'));
writetable(array2table([subjOrder(:) EFF], 'VariableNames', {'sub','pre_dB','post_dB'}), ...
    fullfile(OUT,'tf_cluster_effect_persubject.csv'));
fprintf('\nwrote tf_covariate_summary.csv and tf_cluster_effect_persubject.csv\n');

% getcol() lives in analysis/functions/ (shared with the time-domain script).
