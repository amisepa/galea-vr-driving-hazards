%% Galea statistical analysis at group level of ERP data.
%
% Cedric Cannard, May 2025

clear; close all; clc
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
data_path = paths.data;
cd(data_path)
% Was results_new, now archived outside the repository (Proton Drive study
% archive), so every cardiac number in the
% manuscript had to be typed by hand and could not be checked or re-derived.
output_path = paths.res_cardiac;
load(fullfile(data_path, 'sInfo_ppg.mat'))
% load(fullfile(data_path, 'chanlocs.mat'))
% This addpath was commented out, which makes the script die partway through the
% hierarchical GLM with "Unrecognized function or variable 'compute_wls_weights'"
% - that function lives in this folder and is called from inside
% run_stats_permutation_glm_hierarchical. Keep it.
addpath(paths.robust)
addpath(fullfile(paths.robust, 'functions'))

% NOTE ON GRAPHICS. This script draws 24 figures. MATLAB graphics hang in
% headless -batch mode on this machine, so it must be run from the desktop.

% Get subject list more efficiently
subject_list = dir(data_path);
subject_list = subject_list(contains({subject_list.name}, 'sub-'));

% Remove pilot subject (sub-000) and subject 11 (disrupted session)
subject_list(strcmp({subject_list.name}, 'sub-000')) = [];
sInfo(contains({sInfo.filepath}, 'sub-011')) = [];
subject_list(strcmp({subject_list.name}, 'sub-011')) = [];
nSub = length(subject_list);

% nElecs = 12;
% nFrames = 744;
% [CRASH_TRIALS, NOCRASH_TRIALS] = deal(cell(nSub, 1));
CRASH_TRIALS = {};
NOCRASH_TRIALS = {};
CRASH = [];
NOCRASH = [];
% CRASH = nan(nElecs, nFrames, nSub);
% NOCRASH = nan(nElecs, nFrames, nSub);
bad_subjects = zeros(nSub,1);
for iSub = 1:nSub
    fprintf('Pulling data from subject %g/%g\n', iSub, nSub)

    subFolder = fullfile(data_path, subject_list(iSub).name);
    hrFile = fullfile(subFolder, 'ERP_PPG.mat');

    % Only load if file exists
    % if isfile(eegFile)
    try
        data = load(hrFile);
    catch
        warning("no file for this subject.")
        bad_subjects(iSub) = true;
        continue
    end

    % % Subject 11 file was disconnected before end, so we have to merge
    % % the 2 files to not loose that subject
    % if strcmpi(extractAfter(subFolder, data_path), '\sub-011')
    %     data2 = load(fullfile(subFolder, 'ERP_PPG2.mat'));
    %     merged_crash_data = cat(2, data.crash, data2.crash);
    %     merged_nocrash_data = cat(2, data.nocrash, data2.nocrash);
    %     data.crash = merged_crash_data;
    %     data.nocrash = merged_nocrash_data;
    %     % continue
    % end
        
    % Check if required fields exist
    % try
    % if isfield(data, 'crash') && isfield(data, 'no_crash')
    CRASH_TRIALS{iSub} = data.crash;
    NOCRASH_TRIALS{iSub} = data.nocrash;
    
    % % CRASH(:,:,iSub)= trimmean(data.crash.data, 20, 3);
    % % NOCRASH(:,:,iSub) = trimmean(data.no_crash.data, 20, 3);
    CRASH(:,iSub)= mean(data.crash, 2,'omitnan');
    NOCRASH(:,iSub) = mean(data.nocrash, 2,'omitnan');
    % CRASH(:,iSub) = compute_robust_erp(data.crash, 'huber');
    % NOCRASH(:,iSub) = compute_robust_erp(data.nocrash, 'huber');
    % TIME(:,:,iSub) = data.crash.times;
    
    % % within-subject GLM
    % [betas,rsquared,f,pvals,t] = run_glm_limo_style(EEG.data,times,tlims,EEG.event,optimization,weightmethod);
    % BETAS(:,:,:,iSub) = betas;  % store group level
    % F(:,:,iSub) = fstat;
    % R2(:,:,iSub) = rsquared;
    % P(:,:,iSub) = pvals;

    % else
    % warning('Subject %s: crash/no_crash variables not found', subject_list(iSub).name);
    % end
    % catch
    % warning("Failed to gather crash or no-crash data for this file")
    % end
    % end
end

%% Remove subjects that could not be loaded (i.e. bad subjects)

sInfo(logical(bad_subjects)) = [];
subject_list(logical(bad_subjects)) = [];
nSub = length(sInfo);
fprintf("Total number of subjects remaining: %g\n", nSub)

%%  Remove reminaing bad subjects (if any)

% bad_subjects = cellfun(@isempty, CRASH_TRIALS) | squeeze(any(any(isnan(CRASH),1),2));
bad_subjects = cellfun(@(x) isempty(x) || (isnumeric(x) && all(isnan(x(:)))), CRASH_TRIALS);
% bad_subjects = cellfun(@(x) isempty(x), {sInfo.best_chan});
% bad_subjects = squeeze(any(any(isnan(CRASH),1),2));
if any(bad_subjects)
    warning("Removing %g bad subjects!",sum(bad_subjects))
    disp({subject_list(bad_subjects).name})
    % subject_list(bad_subjects) = [];
    % sInfo(bad_subjects) = [];
    CRASH_TRIALS(bad_subjects) = [];
    NOCRASH_TRIALS(bad_subjects) = [];
    CRASH(:,bad_subjects) = [];
    NOCRASH(:,bad_subjects) = [];
    % TIME(:,:,bad_subjects) = [];
end
nSub = length(CRASH_TRIALS);
fprintf("Total number of subjects remaining: %g\n", nSub)

%% Summary statistics of preprocessings for paper


% Best channel and SNR per subject
fprintf('\n%-8s %-12s %-10s %-10s %-15s\n', 'Subject', 'BestChan', 'SNR_best', 'SNR_other', 'BadBeats(%)');
fprintf('%s\n', repmat('-',1,60));
pct_bad = nan(1, numel(sInfo));
for i = 1:numel(sInfo)
    best   = sInfo(i).best_chan;
    snr_v  = sInfo(i).SNR;       % 1x2 vector (PPG, PPG_IR)
    snr2_v = sInfo(i).SNR2;
    ib     = sInfo(i).idx_bad;
    pct    = sum(ib) / numel(ib) * 100;
    pct_bad(i) = pct;

    % Identify which channel index is best
    chan_labels = {'PPG', 'PPG_IR'};
    best_idx    = find(strcmpi(chan_labels, best), 1);
    other_idx   = setdiff(1:2, best_idx);

    fprintf('%-8d %-12s %-10.1f %-10.1f %-15.1f\n', ...
        sInfo(i).subject, best, snr_v(best_idx), snr_v(other_idx), pct);
end
fprintf('\nBad beats across subjects — mean = %.1f%%, SD = %.1f%% (range: %.1f%%–%.1f%%)\n', ...
    mean(pct_bad), std(pct_bad), min(pct_bad), max(pct_bad));

nCrash   = [sInfo.n_crash_trials];
nNoCrash = [sInfo.n_nocrash_trials];
fprintf('Trials per subject — Crash:   mean = %.1f, SD = %.1f (range: %d–%d)\n', ...
    mean(nCrash),   std(nCrash),   min(nCrash),   max(nCrash));
fprintf('Trials per subject — NoCrash: mean = %.1f, SD = %.1f (range: %d–%d)\n', ...
    mean(nNoCrash), std(nNoCrash), min(nNoCrash), max(nNoCrash));


%% Plot mean + 95% CIs

plotDiff(data.time, NOCRASH, CRASH, 'mean', 'CI', [], 'no crash','crash');   % 'SE' or 'CI'
subplot(2,1,1)
title('Event-related heart rate at the group level');
ylabel('HR (in bpm)')
subplot(2,1,2)
ylabel('Difference (in bpm)'); xlabel("Time (s)")
set(gcf,'Toolbar','none','Menu','none','NumberTitle', 'Off'); 
set(findall(gcf, 'type', 'axes'), 'FontSize', 14, 'FontWeight', 'bold');

%% Simple paired permutation t-test - Heart Rate

nPerm  = 1000;   % can afford more perms with only 11 time points
alpha  = 0.05;
tlims  = [-5 5];  % in seconds (match your time vector units)
out_path = fullfile(output_path, 'HR'); mkdir(out_path)

time     = data.time;
time_idx = time >= tlims(1) & time <= tlims(2);
time     = time(time_idx);
nTime    = sum(time_idx);
nSub     = size(CRASH, 2);

% Subject-averaged condition means [nTime x nSub]
crash   = CRASH(time_idx, :);
nocrash = NOCRASH(time_idx, :);

% Difference per subject [nTime x nSub]
diff_data = crash - nocrash;

% Observed paired t-statistic at each time point
diff_mean = mean(diff_data, 2);           % [nTime x 1]
diff_se   = std(diff_data, 0, 2) / sqrt(nSub);
tvals_obs = diff_mean ./ diff_se;         % [nTime x 1]

% Permutation: flip signs randomly within subjects (equivalent to
% permuting condition labels in a paired design)
tvals_H0 = zeros(nTime, nPerm);
for iPerm = 1:nPerm
    signs = sign(randn(1, nSub));                    % +1 or -1 per subject
    diff_perm = diff_data .* signs;                  % flip some subjects
    m = mean(diff_perm, 2);
    s = std(diff_perm, 0, 2) / sqrt(nSub);
    tvals_H0(:, iPerm) = m ./ s;
end

% Uncorrected p-values
pvals = mean(abs(tvals_H0) >= abs(tvals_obs), 2);   % [nTime x 1]

% t-max correction (most appropriate for 11 time points)
tmax_dist = max(abs(tvals_H0), [], 1);               % [1 x nPerm]
tmax_thresh = prctile(tmax_dist, 100*(1-alpha));
mask_tmax = abs(tvals_obs) >= tmax_thresh;

% Cohen's d_z (paired effect size)
dz = diff_mean ./ std(diff_data, 0, 2);              % [nTime x 1]

% Print results table
fprintf('\n%-10s %-8s %-8s %-10s %-8s\n', ...
    'Time(s)', 't-val', 'p-uncorr', 'sig(tmax)?', 'Cohen_dz');
fprintf('%s\n', repmat('-', 1, 55));
for iT = 1:nTime
    if pvals(iT) <= alpha
        sig_uncorr = 'yes';
    else
        sig_uncorr = 'no';
    end
    if mask_tmax(iT)
        sig_tmax = 'yes';
    else
        sig_tmax = 'no';
    end
    fprintf('%-10.2f %-8.3f %-8.3f %-10s %-8.3f\n', ...
        time(iT), tvals_obs(iT), pvals(iT), sig_tmax, dz(iT));
end

% Plot
figure;
subplot(2,1,1)
plotDiff(time, nocrash, crash, 'mean', 'CI', [], 'No Crash', 'Crash');
title('Heart rate: Crash vs. No Crash');
ylabel('HR (bpm)');

subplot(2,1,2); hold on
plot(time, tvals_obs, 'k.-', 'LineWidth', 1.5, 'MarkerSize', 16);
yline(0,  '--', 'Color', [0.5 0.5 0.5]);
yline( tmax_thresh, 'r--', 'LineWidth', 1.2);
yline(-tmax_thresh, 'r--', 'LineWidth', 1.2);
if any(mask_tmax)
    plot(time(mask_tmax), tvals_obs(mask_tmax), 'ro', ...
        'MarkerSize', 10, 'MarkerFaceColor', 'r');
end
xlabel('Time (s)'); ylabel('t-value (paired)');
title(sprintf('Paired permutation t-test | t-max thresh=%.2f | alpha=%.2f', ...
    tmax_thresh, alpha));
legend('t-value', '', 't-max threshold', '', 'significant', 'Location','best');
set(gcf, 'Toolbar','none','Menu','none','NumberTitle','Off');
set(findall(gcf,'type','axes'), 'FontSize', 14, 'FontWeight', 'bold');

saveas(gcf, fullfile(out_path, 'HR_paired_permutation.fig'));
print(gcf,  fullfile(out_path, 'HR_paired_permutation.png'), '-dpng', '-r300');


%% Linear Mixed Effects Model - Heart Rate (trial-level)

% tlims    = [-5 5];
% alpha    = 0.05;
% out_path = fullfile(output_path, 'HR', 'LME'); mkdir(out_path)
% 
% time     = data.time;
% time_idx = time >= tlims(1) & time <= tlims(2);
% time_vec = time(time_idx);
% nTime    = sum(time_idx);
% nSub     = length(CRASH_TRIALS);
% 
% % ----- Build long-format table from trial-level data -----
% % Each row = one trial x one time point
% rows_crash   = sum(cellfun(@(x) size(x,2), CRASH_TRIALS))   * nTime;
% rows_nocrash = sum(cellfun(@(x) size(x,2), NOCRASH_TRIALS)) * nTime;
% nObs = rows_crash + rows_nocrash;
% 
% SubjectID  = zeros(nObs, 1);
% Condition  = zeros(nObs, 1);
% TimePoint  = zeros(nObs, 1);
% HR_val     = zeros(nObs, 1);
% 
% row = 1;
% for iSub = 1:nSub
%     crash_sub   = CRASH_TRIALS{iSub}(time_idx, :);    % [nTime x nTrials_crash]
%     nocrash_sub = NOCRASH_TRIALS{iSub}(time_idx, :);  % [nTime x nTrials_nocrash]
%     nT_crash   = size(crash_sub, 2);
%     nT_nocrash = size(nocrash_sub, 2);
% 
%     % Crash trials
%     for iTrial = 1:nT_crash
%         for iT = 1:nTime
%             SubjectID(row) = iSub;
%             Condition(row) = 1;
%             TimePoint(row) = time_vec(iT);
%             HR_val(row)    = crash_sub(iT, iTrial);
%             row = row + 1;
%         end
%     end
% 
%     % No-crash trials
%     for iTrial = 1:nT_nocrash
%         for iT = 1:nTime
%             SubjectID(row) = iSub;
%             Condition(row) = 0;
%             TimePoint(row) = time_vec(iT);
%             HR_val(row)    = nocrash_sub(iT, iTrial);
%             row = row + 1;
%         end
%     end
% end
% 
% T = table(SubjectID, Condition, TimePoint, HR_val, ...
%     'VariableNames', {'Subject','Condition','Time','HR'});
% T.Subject   = categorical(T.Subject);
% T.Condition = categorical(T.Condition);
% 
% fprintf('Table built: %d rows (%d crash trials, %d nocrash trials across %d subjects)\n', ...
%     nObs, rows_crash/nTime, rows_nocrash/nTime, nSub);
% 
% % ----- Global LME -----
% % Random intercept only
% lme1 = fitlme(T, 'HR ~ Condition + Time + Condition:Time + (1|Subject)', ...
%     'FitMethod', 'REML');
% 
% % Random intercept + random slope for condition
% % (allows each subject to have their own crash vs nocrash difference)
% lme2 = fitlme(T, 'HR ~ Condition + Time + Condition:Time + (1|Subject) + (Condition-1|Subject)', ...
%     'FitMethod', 'REML');
% 
% fprintf('\n=== MODEL COMPARISON ===\n');
% compare(lme1, lme2)
% 
% fprintf('\n=== LME1 RESULTS (random intercept) ===\n');
% disp(lme1.Coefficients)
% fprintf('\n=== LME2 RESULTS (random intercept + slope) ===\n');
% disp(lme2.Coefficients)
% 
% % Use better-fitting model
% lme = lme2;
% 
% % ----- Time-point LME -----
% fprintf('\n=== TIME-POINT LME ===\n');
% tvals_lme = zeros(nTime, 1);
% pvals_lme = zeros(nTime, 1);
% beta_lme  = zeros(nTime, 1);
% ci_lme    = zeros(nTime, 2);
% 
% for iT = 1:nTime
%     idx = T.Time == time_vec(iT);
%     T_t = T(idx, :);
% 
%     % Random intercept + slope per time point
%     lme_t = fitlme(T_t, 'HR ~ Condition + (1|Subject) + (Condition-1|Subject)', ...
%         'FitMethod', 'REML');
% 
%     coeffs   = lme_t.Coefficients;
%     cond_row = strcmp(coeffs.Name, 'Condition_1');
%     tvals_lme(iT) = coeffs.tStat(cond_row);
%     pvals_lme(iT) = coeffs.pValue(cond_row);
%     beta_lme(iT)  = coeffs.Estimate(cond_row);
%     ci_lme(iT,:)  = [coeffs.Lower(cond_row) coeffs.Upper(cond_row)];
% end
% 
% % FDR correction
% try
%     pvals_fdr = mafdr(pvals_lme, 'BHFDR', true);
% catch
%     [~, sort_idx] = sort(pvals_lme);
%     pvals_fdr = zeros(nTime, 1);
%     fdr_thresh = (1:nTime)' / nTime * alpha;
%     pvals_fdr(sort_idx) = pvals_lme(sort_idx);  
%     % manual BH adjusted p
%     for k = nTime:-1:1
%         if k == nTime
%             pvals_fdr(sort_idx(k)) = pvals_lme(sort_idx(k));
%         else
%             pvals_fdr(sort_idx(k)) = min(pvals_lme(sort_idx(k)) * nTime/k, ...
%                                          pvals_fdr(sort_idx(k+1)));
%         end
%     end
% end
% mask_fdr = pvals_fdr <= alpha;
% 
% % Print
% fprintf('\n%-10s %-10s %-10s %-10s %-10s %-10s\n', ...
%     'Time(s)', 'Beta(bpm)', 'CI_lo', 'CI_hi', 't', 'p_fdr');
% fprintf('%s\n', repmat('-',1,65));
% for iT = 1:nTime
%     if mask_fdr(iT), sig_str = ' *'; else, sig_str = ''; end
%     fprintf('%-10.2f %-10.3f %-10.3f %-10.3f %-10.3f %-10.4f%s\n', ...
%         time_vec(iT), beta_lme(iT), ci_lme(iT,1), ci_lme(iT,2), ...
%         tvals_lme(iT), pvals_fdr(iT), sig_str);
% end

%% ----- Plot -----

% figure('Position', [100 100 860 680], 'Color', 'w', ...
%     'Toolbar', 'none', 'Menu', 'none', 'NumberTitle', 'Off');
% 
% col_crash   = [0.78 0.18 0.18];
% col_nocrash = [0.13 0.45 0.74];
% col_diff    = [0.25 0.25 0.25];
% col_zero    = [0.75 0.75 0.75];
% col_subj    = [0.80 0.80 0.80];
% 
% crash_mean   = mean(CRASH(time_idx,:), 2);
% nocrash_mean = mean(NOCRASH(time_idx,:), 2);
% crash_ci     = 1.96 * std(CRASH(time_idx,:),   0, 2) / sqrt(nSub);
% nocrash_ci   = 1.96 * std(NOCRASH(time_idx,:), 0, 2) / sqrt(nSub);
% diff_mean    = crash_mean - nocrash_mean;
% diff_ci      = 1.96 * std(CRASH(time_idx,:) - NOCRASH(time_idx,:), 0, 2) / sqrt(nSub);
% subj_diff    = CRASH(time_idx,:) - NOCRASH(time_idx,:);
% 
% % ---- Panel 1: HR mean + 95% CI ----
% ax1 = subplot(3,1,1); hold on;
% 
% fill([time_vec fliplr(time_vec)], ...
%      [nocrash_mean-nocrash_ci; flipud(nocrash_mean+nocrash_ci)]', ...
%      col_nocrash, 'FaceAlpha', 0.12, 'EdgeColor', 'none');
% fill([time_vec fliplr(time_vec)], ...
%      [crash_mean-crash_ci; flipud(crash_mean+crash_ci)]', ...
%      col_crash, 'FaceAlpha', 0.12, 'EdgeColor', 'none');
% xline(0, 'Color', col_zero, 'LineWidth', 1, 'Alpha', 1);
% plot(time_vec, nocrash_mean, '-', 'Color', col_nocrash, 'LineWidth', 2.5);
% plot(time_vec, crash_mean,   '-', 'Color', col_crash,   'LineWidth', 2.5);
% 
% ylabel('HR (bpm)', 'FontSize', 12);
% title('Heart rate: Crash vs. No Crash', 'FontSize', 13, 'FontWeight', 'bold');
% legend({'','','No Crash (n=15)','Crash (n=15)'}, ...
%        'Location', 'northeast', 'FontSize', 10, 'Box', 'off');
% set(ax1, 'XTickLabel', [], 'Box', 'off', 'FontSize', 11, ...
%     'XLim', [time_vec(1) time_vec(end)], 'TickDir', 'out', ...
%     'XGrid', 'off', 'YGrid', 'off');
% 
% % ---- Panel 2: Condition difference ----
% ax2 = subplot(3,1,2); hold on;
% 
% % Individual subjects (very faint)
% for iSub = 1:nSub
%     plot(time_vec, subj_diff(:,iSub), '-', ...
%         'Color', [col_subj 0.35], 'LineWidth', 0.8);
% end
% fill([time_vec fliplr(time_vec)], ...
%      [diff_mean-diff_ci; flipud(diff_mean+diff_ci)]', ...
%      col_diff, 'FaceAlpha', 0.12, 'EdgeColor', 'none');
% xline(0, 'Color', col_zero, 'LineWidth', 1, 'Alpha', 1);
% yline(0, 'Color', col_zero, 'LineWidth', 1, 'Alpha', 1);
% plot(time_vec, diff_mean, '-', 'Color', col_diff, 'LineWidth', 2.5);
% 
% % ylabel('Crash \minus No Crash (bpm)', 'FontSize', 12);
% ylabel('Crash - No Crash (bpm)', 'FontSize', 12);
% title('Condition difference', 'FontSize', 13, 'FontWeight', 'bold');
% set(ax2, 'XTickLabel', [], 'Box', 'off', 'FontSize', 11, ...
%     'XLim', [time_vec(1) time_vec(end)], 'TickDir', 'out', ...
%     'XGrid', 'off', 'YGrid', 'off');
% 
% % ---- Panel 3: LME t-values ----
% ax3 = subplot(3,1,3); hold on;
% 
% yline(0, 'Color', col_zero, 'LineWidth', 1, 'Alpha', 1);
% xline(0, 'Color', col_zero, 'LineWidth', 1, 'Alpha', 1);
% 
% % Shade non-significant region (±~2)
% ylims_t = [-3 2];
% fill([time_vec(1) time_vec(end) time_vec(end) time_vec(1)], ...
%      [-2 -2 2 2], [0.93 0.93 0.93], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
% 
% plot(time_vec, tvals_lme, '-', 'Color', col_diff, 'LineWidth', 2.5);
% 
% % Annotate best (uncorrected) p-value only
% [~, best_t] = max(abs(tvals_lme));
% text(time_vec(best_t), tvals_lme(best_t) - 0.25, ...
%     sprintf('p_{uncorr}=%.3f', pvals_lme(best_t)), ...
%     'FontSize', 9, 'HorizontalAlignment', 'center', 'Color', [0.4 0.4 0.4]);
% 
% % Add "n.s." label
% text(time_vec(end)-0.3, ylims_t(2)-0.25, 'all n.s. (FDR)', ...
%     'FontSize', 9, 'HorizontalAlignment', 'right', 'Color', [0.55 0.55 0.55]);
% 
% ylabel('t-value (LME)', 'FontSize', 12);
% xlabel('Time relative to event (s)', 'FontSize', 12);
% title('LME condition effect per time point', 'FontSize', 13, 'FontWeight', 'bold');
% ylim(ylims_t);
% set(ax3, 'Box', 'off', 'FontSize', 11, ...
%     'XLim', [time_vec(1) time_vec(end)], 'TickDir', 'out', ...
%     'XGrid', 'off', 'YGrid', 'off');
% 
% linkaxes([ax1 ax2 ax3], 'x');
% 
% % Consistent spacing
% set(ax1, 'Position', get(ax1,'Position') + [0 0 0 0.02]);
% set(ax2, 'Position', get(ax2,'Position') + [0 0 0 0.02]);
% set(ax3, 'Position', get(ax3,'Position') + [0 0 0 0.02]);
% 
% saveas(gcf, fullfile(out_path, 'HR_LME_clean.fig'));
% print(gcf,  fullfile(out_path, 'HR_LME_clean.png'), '-dpng', '-r300');


%% 2-level Hierarchical GLM - Heart Rate - POST-STIMULUS PERIOD

optim      = 'WLS';
weight     = 'Huber';
nPerm      = 1000;
alpha      = 0.05;
grp_type   = 'dpt';
mcc_type   = 1;
chanlocs   = [];
es         = 'd';
tlims      = [0 5];
out_path   = fullfile(output_path, 'HR', 'post-stim', optim); mkdir(out_path)

time     = data.time;
time_idx = time >= tlims(1) & time <= tlims(2);
time     = time(time_idx);
nTime    = sum(time_idx);
nSub     = length(CRASH_TRIALS);

% Trim to time window and add singleton channel dim: [1 x nTime x nTrials]
% Each cell: [nTime x nTrials] -> [1 x nTime x nTrials]
crash_cells   = cellfun(@(x) reshape(x(time_idx,:), 1, nTime, []), CRASH_TRIALS,   'uni', false);
nocrash_cells = cellfun(@(x) reshape(x(time_idx,:), 1, nTime, []), NOCRASH_TRIALS, 'uni', false);

% Stack across subjects into [1 x nTime x totalTrials]
Y_crash   = cat(3, crash_cells{:});
Y_nocrash = cat(3, nocrash_cells{:});
Y_all     = cat(3, Y_crash, Y_nocrash);

% Subject and condition indices
n_crash   = cellfun(@(x) size(x,3), crash_cells);
n_nocrash = cellfun(@(x) size(x,3), nocrash_cells);
subj_idx      = [repelem(1:nSub, n_crash), repelem(1:nSub, n_nocrash)]';
condition_col = [ones(sum(n_crash),1); zeros(sum(n_nocrash),1)];
X             = [ones(length(condition_col),1), condition_col];

fprintf('Total trials: %d (crash=%d, nocrash=%d)\n', size(Y_all,3), sum(n_crash), sum(n_nocrash));

[betas, tvals, tvals_H0, weights, pvals, pvals_H0, dz] = run_stats_permutation_glm_hierarchical( ...
    Y_all, X, condition_col, nSub, nPerm, 'Subjects', subj_idx, ...
    'Method', optim, 'WeightType', weight, 'Progress', true);

% Squeeze singleton channel dim for plotting
tvals_vec = squeeze(tvals);   % [nTime x 1]
mask      = compute_mcc(tvals, pvals, tvals_H0, pvals_H0, mcc_type, alpha, chanlocs);
mask_vec  = squeeze(mask);

% Plot
figure;
subplot(2,1,1)
plotDiff(time, NOCRASH(time_idx,:), CRASH(time_idx,:), 'mean', 'CI', [], 'No Crash', 'Crash');
title('Heart rate: Crash vs. No Crash (post-stimulus)');
ylabel('HR (bpm)');
subplot(2,1,2)
plot(time, tvals_vec, 'k', 'LineWidth', 1.5); hold on
if any(mask_vec)
    sig_t = tvals_vec; sig_t(~mask_vec) = NaN;
    plot(time, sig_t, 'r', 'LineWidth', 2.5);
end
yline(0, '--', 'Color', [0.5 0.5 0.5]);
xlabel('Time (s)'); ylabel('t-value');
title(sprintf('GLM t-values (mcc=%d, alpha=%.2f)', mcc_type, alpha));
set(gcf, 'Toolbar','none','Menu','none','NumberTitle','Off');
set(findall(gcf,'type','axes'), 'FontSize', 14, 'FontWeight', 'bold');

saveas(gcf, fullfile(out_path, sprintf('HR_post_corr-%d.fig', mcc_type)));
print(gcf,  fullfile(out_path, sprintf('HR_post_corr-%d.png', mcc_type)), '-dpng', '-r300');


%% PRE-STIMULUS PERIOD

tlims    = [-5 0];
out_path = fullfile(output_path, 'HR', 'pre-stim', optim); mkdir(out_path)

time     = data.time;
time_idx = time >= tlims(1) & time <= tlims(2);
time     = time(time_idx);
nTime    = sum(time_idx);

crash_cells   = cellfun(@(x) reshape(x(time_idx,:), 1, nTime, []), CRASH_TRIALS,   'uni', false);
nocrash_cells = cellfun(@(x) reshape(x(time_idx,:), 1, nTime, []), NOCRASH_TRIALS, 'uni', false);

Y_crash   = cat(3, crash_cells{:});
Y_nocrash = cat(3, nocrash_cells{:});
Y_all     = cat(3, Y_crash, Y_nocrash);

n_crash   = cellfun(@(x) size(x,3), crash_cells);
n_nocrash = cellfun(@(x) size(x,3), nocrash_cells);
subj_idx      = [repelem(1:nSub, n_crash), repelem(1:nSub, n_nocrash)]';
condition_col = [ones(sum(n_crash),1); zeros(sum(n_nocrash),1)];
X             = [ones(length(condition_col),1), condition_col];

[betas, tvals, tvals_H0, weights, pvals, pvals_H0, dz] = run_stats_permutation_glm_hierarchical( ...
    Y_all, X, condition_col, nSub, nPerm, 'Subjects', subj_idx, ...
    'Method', optim, 'WeightType', weight, 'Progress', true);

tvals_vec = squeeze(tvals);
mask      = compute_mcc(tvals, pvals, tvals_H0, pvals_H0, mcc_type, alpha, chanlocs);
mask_vec  = squeeze(mask);

figure;
subplot(2,1,1)
plotDiff(time, NOCRASH(time_idx,:), CRASH(time_idx,:), 'mean', 'CI', [], 'No Crash', 'Crash');
title('Heart rate: Crash vs. No Crash (pre-stimulus)');
ylabel('HR (bpm)');
subplot(2,1,2)
plot(time, tvals_vec, 'k', 'LineWidth', 1.5); hold on
if any(mask_vec)
    sig_t = tvals_vec; sig_t(~mask_vec) = NaN;
    plot(time, sig_t, 'r', 'LineWidth', 2.5);
end
yline(0, '--', 'Color', [0.5 0.5 0.5]);
xlabel('Time (s)'); ylabel('t-value');
title(sprintf('GLM t-values (mcc=%d, alpha=%.2f)', mcc_type, alpha));
set(gcf, 'Toolbar','none','Menu','none','NumberTitle','Off');
set(findall(gcf,'type','axes'), 'FontSize', 14, 'FontWeight', 'bold');

saveas(gcf, fullfile(out_path, sprintf('HR_pre_corr-%d.fig', mcc_type)));
print(gcf,  fullfile(out_path, sprintf('HR_pre_corr-%d.png', mcc_type)), '-dpng', '-r300');


%% GATHER QUESTIONNAIRE DATA FOR HIERARCHICHAL GLM + COVARIATES
%   1. Loads questionnaire data from Excel, matches to ERP subjects
%   2. Lets you select which covariate to include in the hierarchical GLM
%   3. Runs the analysis with the selected covariate
close all

% 1. LOAD AND MATCH QUESTIONNAIRE DATA
quest_file = paths.questionnaires;
raw = readtable(quest_file, 'Sheet', 'IDs');

% ERP subject IDs (from subject_list)
erp_ids = {subject_list.name};  % e.g., {'sub-001', 'sub-002', ...}
nSub = length(erp_ids);

% Normalize IDs for matching: 'Sub_001' → 'sub-001'
quest_ids = cellfun(@(x) lower(strrep(x, '_', '-')), raw.RespondentID, 'uni', false);

% Find matching rows
match_idx = zeros(nSub, 1);
for iSub = 1:nSub
    idx = find(strcmp(quest_ids, erp_ids{iSub}));
    if isempty(idx)
        error('Subject %s not found in questionnaire data!', erp_ids{iSub});
    end
    match_idx(iSub) = idx(1);
end
fprintf('All %d ERP subjects matched in questionnaire data.\n', nSub);

% 2. EXTRACT QUESTIONNAIRE VARIABLES

% Numeric Likert encoding for Big Five (TIPI-10)
likert_map = containers.Map( ...
    {'Strongly disagree', 'Disagree', 'Neither agree nor disagree', 'Agree', 'Strongly agree'}, ...
    {1, 2, 3, 4, 5});

% Build questionnaire table for matched subjects
Q = table();
Q.subject = erp_ids(:);

% --- Extract numeric variables ---
% Age
Q.age = raw{match_idx, 'PleaseEnterYourAge'};

% Sex at birth (encode: Male=0, Female=1)
sex_raw = raw{match_idx, 'WhatIsYourSexAtBirth_'};
if iscell(sex_raw)
    Q.sex = double(strcmpi(sex_raw, 'Female'));
else
    Q.sex = nan(nSub, 1);
end

% Education (years)
Q.education = raw{match_idx, 'HowManyYearsOfFormalEducation_school_HaveYouCompleted__ForExample_12Years_HighSchoolDiploma_16Years_Bachelor_sDegree_'};

% Driving experience (0-10 scale)
Q.driving = raw{match_idx, 'HowWouldYouRateYourExperienceOrLevelAtDriving_orPiloting_AVehicle_orAircraftIfApplicable__'};

% Sports proficiency (0-10 scale)
Q.sports = raw{match_idx, 'HowWouldYouAssessYourProficiencyOrExperienceInSports_'};

% Video game experience (0-10 scale)
Q.videogames = raw{match_idx, 'HowWouldYouRateYourExperienceOrLevelAtPlayingVideoGames_'};

% Meditation experience (0-10 scale)
Q.meditation = raw{match_idx, 'HowWouldYouRateYourExperienceOrLevelOfMeditating_'};

% Intuition belief (encode: Yes=1, No=0, I don't know=0.5)
intuit_raw = raw{match_idx, 'DoYouBelieveInIntuitionOr_gutFeelings__'};
if iscell(intuit_raw)
    Q.intuition = nan(nSub, 1);
    Q.intuition(strcmpi(intuit_raw, 'Yes')) = 1;
    Q.intuition(strcmpi(intuit_raw, 'No')) = 0;
    Q.intuition(contains(intuit_raw, 'know', 'IgnoreCase', true)) = 0.5;
else
    Q.intuition = nan(nSub, 1);
end

% --- Big Five (TIPI-10) ---
bf_varnames = { ...
    'x1_ISeeMyselfAsExtraverted_Enthusiastic', ...
    'x2_ISeeMyselfAsReserved_Quiet_', ...
    'x3_ISeeMyselfAsSympathetic_Warm_', ...
    'x4_ISeeMyselfAsCritical_Quarrelsome_', ...
    'x5_ISeeMyselfAsDependable_Self_disciplined_', ...
    'x6_ISeeMyselfAsDisorganized_Careless_', ...
    'x7_ISeeMyselfAsCalm_EmotionallyStable_', ...
    'x8_ISeeMyselfAsAnxious_EasilyUpset_', ...
    'x9_ISeeMyselfAsOpenToNewExperiences_Complex_', ...
    'x10_ISeeMyselfAsConventional_Uncreative_'};
bf_data = raw(match_idx, bf_varnames);

% Convert Likert text to numbers
bf_numeric = nan(nSub, 10);
for iItem = 1:10
    col_data = bf_data{:, iItem};
    if iscell(col_data)
        for iSub = 1:nSub
            if ischar(col_data{iSub}) && likert_map.isKey(col_data{iSub})
                bf_numeric(iSub, iItem) = likert_map(col_data{iSub});
            end
        end
    end
end

% Compute Big Five dimensions (TIPI scoring: positive + (6 - reverse))
Q.extraversion     = (bf_numeric(:,1) + (6 - bf_numeric(:,2))) / 2;
Q.agreeableness    = (bf_numeric(:,3) + (6 - bf_numeric(:,4))) / 2;
Q.conscientiousness = (bf_numeric(:,5) + (6 - bf_numeric(:,6))) / 2;
Q.emotional_stability = (bf_numeric(:,7) + (6 - bf_numeric(:,8))) / 2;
Q.openness         = (bf_numeric(:,9) + (6 - bf_numeric(:,10))) / 2;

% Display the questionnaire data
fprintf('\n=== QUESTIONNAIRE DATA ===\n');
disp(Q);

% Check for missing data
missing = sum(ismissing(Q{:, 2:end}), 1);
var_names = Q.Properties.VariableNames(2:end);
for i = 1:length(var_names)
    if missing(i) > 0
        fprintf('WARNING: %s has %d missing values\n', var_names{i}, missing(i));
    end
end


%% Questionnaire correlations with HR condition effect (skipped Spearman)

excluded_from_hr = {'sub-018'};
hr_mask = ~ismember(Q.subject, excluded_from_hr);
Q_hr = Q(hr_mask, :);
fprintf('Q_hr: %d subjects\n', height(Q_hr));

out_path = fullfile(output_path, 'HR', 'questionnaire_correlations');
mkdir(out_path);

% HR condition effect per subject (post-stimulus)
tlims    = [0 5];
time     = data.time;
time_idx = time >= tlims(1) & time <= tlims(2);
crash_mean_subj   = mean(CRASH(time_idx,:), 1);
nocrash_mean_subj = mean(NOCRASH(time_idx,:), 1);
hr_effect = (crash_mean_subj - nocrash_mean_subj)';   % [nSub x 1]

cov_names = {'age','sex','education','driving','sports','videogames', ...
             'meditation','intuition','extraversion','agreeableness', ...
             'conscientiousness','emotional_stability','openness'};
nCov  = length(cov_names);
rvals = zeros(nCov, 1);
pvals = zeros(nCov, 1);
n_outliers = zeros(nCov, 1);

fprintf('\n=== HR CONDITION EFFECT x QUESTIONNAIRE CORRELATIONS (skipped Spearman) ===\n');
fprintf('HR metric: mean(crash) - mean(nocrash), post-stimulus [%g %g s]\n\n', tlims(1), tlims(2));
fprintf('%-25s %-8s %-10s %-10s %-12s\n', 'Variable', 'n_out', 'rho', 'p', 'sig');
fprintf('%s\n', repmat('-', 1, 65));

for iCov = 1:nCov
    cov_vals = Q_hr.(cov_names{iCov});
    cov_vals = cov_vals(:);

    % Remove NaNs first
    valid = ~isnan(cov_vals) & ~isnan(hr_effect);
    X = [cov_vals(valid), hr_effect(valid)];

    % Detect bivariate outliers
    flag = bivariate_outliers(X);
    keep = flag == 0;
    n_outliers(iCov) = sum(~keep);
    X_clean = X(keep, :);

    % Skipped Spearman on clean data
    [r, p] = corr(X_clean(:,1), X_clean(:,2), 'Type', 'Spearman');
    rvals(iCov) = r;
    pvals(iCov) = p;

    sig_str = '';
    if p < 0.05,  sig_str = '*';  end
    if p < 0.01,  sig_str = '**'; end
    fprintf('%-25s %-8d %-10.3f %-10.4f %-12s\n', ...
        cov_names{iCov}, n_outliers(iCov), r, p, sig_str);
end

% BH-FDR correction
[~, sort_idx] = sort(pvals);
pvals_fdr = zeros(nCov, 1);
for k = nCov:-1:1
    if k == nCov
        pvals_fdr(sort_idx(k)) = pvals(sort_idx(k));
    else
        pvals_fdr(sort_idx(k)) = min(pvals(sort_idx(k)) * nCov/k, ...
                                     pvals_fdr(sort_idx(k+1)));
    end
end
mask_fdr = pvals_fdr <= 0.05;
fprintf('\nFDR-corrected significant: %d/%d\n', sum(mask_fdr), nCov);

% Bar chart
[~, sort_r] = sort(abs(rvals), 'descend');

figure('Position', [100 100 800 500], 'Color', 'w', ...
    'Toolbar', 'none', 'Menu', 'none', 'NumberTitle', 'Off');
ax = axes; hold on;

col_pos = [0.13 0.45 0.74];
col_neg = [0.78 0.18 0.18];
col_sig = [0.1  0.6  0.3];

for i = 1:nCov
    iCov = sort_r(i);
    col  = col_pos;
    if rvals(iCov) < 0, col = col_neg; end
    if mask_fdr(iCov),  col = col_sig; end
    bar(i, rvals(iCov), 'FaceColor', col, 'EdgeColor', 'none', 'BarWidth', 0.6);
    if n_outliers(iCov) > 0
        text(i, -0.05, sprintf('-%d', n_outliers(iCov)), ...
            'FontSize', 7, 'HorizontalAlignment', 'center', 'Color', [0.5 0.5 0.5]);
    end
    if mask_fdr(iCov)
        y_pos = rvals(iCov) + 0.06 * sign(rvals(iCov));
        text(i, y_pos, '*', 'FontSize', 14, 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'Color', col_sig);
    end
end

yline(0, 'Color', [0.7 0.7 0.7], 'LineWidth', 1);
set(ax, 'XTick', 1:nCov, 'XTickLabel', cov_names(sort_r), ...
    'XTickLabelRotation', 35, 'Box', 'off', 'FontSize', 11, ...
    'TickDir', 'out');
ylabel('Spearman rho (skipped)', 'FontSize', 12);
title('HR condition effect vs. questionnaire variables', ...
    'FontSize', 13, 'FontWeight', 'bold');
ylim([-1 1]);

text(nCov-0.5, 0.92, 'positive rho', 'Color', col_pos, 'FontSize', 9, 'HorizontalAlignment', 'right');
text(nCov-0.5, 0.80, 'negative rho', 'Color', col_neg, 'FontSize', 9, 'HorizontalAlignment', 'right');
text(nCov-0.5, 0.68, 'FDR significant', 'Color', col_sig, 'FontSize', 9, 'HorizontalAlignment', 'right');
text(nCov-0.5, 0.56, 'gray numbers = outliers removed', 'Color', [0.5 0.5 0.5], 'FontSize', 8, 'HorizontalAlignment', 'right');

saveas(gcf, fullfile(out_path, 'HR_questionnaire_rho_skipped.fig'));
print(gcf,  fullfile(out_path, 'HR_questionnaire_rho_skipped.png'), '-dpng', '-r300');

% Scatter plots for top 3 (with outliers shown but not used)
top3 = sort_r(1:min(3, nCov));

figure('Position', [100 100 900 320], 'Color', 'w', ...
    'Toolbar', 'none', 'Menu', 'none', 'NumberTitle', 'Off');

for i = 1:length(top3)
    iCov     = top3(i);
    cov_vals = Q_hr.(cov_names{iCov});
    cov_vals = cov_vals(:);
    valid    = ~isnan(cov_vals) & ~isnan(hr_effect);
    X        = [cov_vals(valid), hr_effect(valid)];
    flag     = bivariate_outliers(X);
    keep     = flag == 0;

    subplot(1, length(top3), i); hold on;

    % Plot outliers in gray
    if any(~keep)
        scatter(X(~keep,1), X(~keep,2), 50, [0.75 0.75 0.75], 'filled', ...
            'MarkerFaceAlpha', 0.6);
    end
    % Plot clean points
    scatter(X(keep,1), X(keep,2), 50, [0.3 0.3 0.3], 'filled', ...
        'MarkerFaceAlpha', 0.7);

    % Fit line on clean data only
    p_fit = polyfit(X(keep,1), X(keep,2), 1);
    x_fit = linspace(min(X(keep,1)), max(X(keep,1)), 50);
    plot(x_fit, polyval(p_fit, x_fit), '-', 'Color', [0.78 0.18 0.18], 'LineWidth', 2);

    xlabel(cov_names{iCov}, 'FontSize', 11);
    if i == 1, ylabel('HR effect (bpm)', 'FontSize', 11); end
    title(sprintf('rho=%.2f, p=%.3f (-%d out)', ...
        rvals(iCov), pvals(iCov), n_outliers(iCov)), ...
        'FontSize', 10, 'FontWeight', 'normal');
    set(gca, 'Box', 'off', 'FontSize', 10, 'TickDir', 'out');
end

sgtitle('Top correlations: HR condition effect vs. questionnaires (skipped Spearman)', ...
    'FontSize', 11, 'FontWeight', 'bold');

saveas(gcf, fullfile(out_path, 'HR_questionnaire_scatters_skipped.fig'));
print(gcf,  fullfile(out_path, 'HR_questionnaire_scatters_skipped.png'), '-dpng', '-r300');

%% Questionnaire correlations with HR condition effect - PRE-STIMULUS (skipped Spearman)

out_path_pre = fullfile(output_path, 'HR', 'questionnaire_correlations', 'pre-stim');
mkdir(out_path_pre);

tlims_pre    = [-5 0];
time         = data.time;
time_idx_pre = time >= tlims_pre(1) & time <= tlims_pre(2);

crash_mean_subj_pre   = mean(CRASH(time_idx_pre,:),   1);
nocrash_mean_subj_pre = mean(NOCRASH(time_idx_pre,:), 1);
hr_effect_pre         = (crash_mean_subj_pre - nocrash_mean_subj_pre)';  % [nSub x 1]

fprintf('\n=== HR ANTICIPATORY EFFECT x QUESTIONNAIRE CORRELATIONS (skipped Spearman) ===\n');
fprintf('HR metric: mean(crash) - mean(nocrash), pre-stimulus [%g %g s]\n\n', tlims_pre(1), tlims_pre(2));
fprintf('%-25s %-8s %-10s %-10s %-12s\n', 'Variable', 'n_out', 'rho', 'p', 'sig');
fprintf('%s\n', repmat('-', 1, 65));

rvals_pre      = zeros(nCov, 1);
pvals_pre      = zeros(nCov, 1);
n_outliers_pre = zeros(nCov, 1);

for iCov = 1:nCov
    cov_vals = Q_hr.(cov_names{iCov});
    cov_vals = cov_vals(:);

    % Remove NaNs
    valid  = ~isnan(cov_vals) & ~isnan(hr_effect_pre);
    X      = [cov_vals(valid), hr_effect_pre(valid)];

    % Bivariate outlier detection (skip for intuition: near-constant variable)
    if strcmpi(cov_names{iCov}, 'intuition')
        keep = true(size(X, 1), 1);
        n_outliers_pre(iCov) = 0;
        warning('Skipping bivariate outlier detection for intuition (near-constant distribution).');
    else
        flag = bivariate_outliers(X);
        keep = flag == 0;
        n_outliers_pre(iCov) = sum(~keep);
    end

    X_clean = X(keep, :);
    [r, p]  = corr(X_clean(:,1), X_clean(:,2), 'Type', 'Spearman');
    rvals_pre(iCov) = r;
    pvals_pre(iCov) = p;

    sig_str = '';
    if p < 0.05,  sig_str = '*';  end
    if p < 0.01,  sig_str = '**'; end
    fprintf('%-25s %-8d %-10.3f %-10.4f %-12s\n', ...
        cov_names{iCov}, n_outliers_pre(iCov), r, p, sig_str);
end

% BH-FDR correction
[~, sort_idx] = sort(pvals_pre);
pvals_fdr_pre = zeros(nCov, 1);
for k = nCov:-1:1
    if k == nCov
        pvals_fdr_pre(sort_idx(k)) = pvals_pre(sort_idx(k));
    else
        pvals_fdr_pre(sort_idx(k)) = min(pvals_pre(sort_idx(k)) * nCov/k, ...
                                         pvals_fdr_pre(sort_idx(k+1)));
    end
end
mask_fdr_pre = pvals_fdr_pre <= 0.05;
fprintf('\nFDR-corrected significant: %d/%d\n', sum(mask_fdr_pre), nCov);

% Bar chart
[~, sort_r_pre] = sort(abs(rvals_pre), 'descend');

figure('Position', [100 100 800 500], 'Color', 'w', ...
    'Toolbar', 'none', 'Menu', 'none', 'NumberTitle', 'Off');
ax = axes; hold on;

col_pos = [0.13 0.45 0.74];
col_neg = [0.78 0.18 0.18];
col_sig = [0.1  0.6  0.3];

for i = 1:nCov
    iCov = sort_r_pre(i);
    col  = col_pos;
    if rvals_pre(iCov) < 0, col = col_neg; end
    if mask_fdr_pre(iCov),  col = col_sig; end
    bar(i, rvals_pre(iCov), 'FaceColor', col, 'EdgeColor', 'none', 'BarWidth', 0.6);
    if n_outliers_pre(iCov) > 0
        text(i, -0.05, sprintf('-%d', n_outliers_pre(iCov)), ...
            'FontSize', 7, 'HorizontalAlignment', 'center', 'Color', [0.5 0.5 0.5]);
    end
    if mask_fdr_pre(iCov)
        y_pos = rvals_pre(iCov) + 0.06 * sign(rvals_pre(iCov));
        text(i, y_pos, '*', 'FontSize', 14, 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'Color', col_sig);
    end
end

yline(0, 'Color', [0.7 0.7 0.7], 'LineWidth', 1);
set(ax, 'XTick', 1:nCov, 'XTickLabel', cov_names(sort_r_pre), ...
    'XTickLabelRotation', 35, 'Box', 'off', 'FontSize', 11, ...
    'TickDir', 'out', 'XGrid', 'off', 'YGrid', 'off');
ylabel('Spearman rho (skipped)', 'FontSize', 12);
title('Anticipatory HR condition effect vs. questionnaire variables', ...
    'FontSize', 13, 'FontWeight', 'bold');
ylim([-1 1]);

text(nCov-0.5, 0.92, 'positive rho',              'Color', col_pos,         'FontSize', 9, 'HorizontalAlignment', 'right');
text(nCov-0.5, 0.80, 'negative rho',              'Color', col_neg,         'FontSize', 9, 'HorizontalAlignment', 'right');
text(nCov-0.5, 0.68, 'FDR significant',           'Color', col_sig,         'FontSize', 9, 'HorizontalAlignment', 'right');
text(nCov-0.5, 0.56, 'gray numbers = outliers removed', 'Color', [0.5 0.5 0.5], 'FontSize', 8, 'HorizontalAlignment', 'right');

saveas(gcf, fullfile(out_path_pre, 'HR_questionnaire_rho_pre_skipped.fig'));
print(gcf,  fullfile(out_path_pre, 'HR_questionnaire_rho_pre_skipped.png'), '-dpng', '-r300');

% Scatter plots for top 3 (outliers shown in gray)
top3_pre = sort_r_pre(1:min(3, nCov));

figure('Position', [100 100 900 320], 'Color', 'w', ...
    'Toolbar', 'none', 'Menu', 'none', 'NumberTitle', 'Off');

for i = 1:length(top3_pre)
    iCov     = top3_pre(i);
    cov_vals = Q_hr.(cov_names{iCov});
    cov_vals = cov_vals(:);
    valid    = ~isnan(cov_vals) & ~isnan(hr_effect_pre);
    X        = [cov_vals(valid), hr_effect_pre(valid)];

    if strcmpi(cov_names{iCov}, 'intuition')
        keep = true(size(X,1), 1);
    else
        flag = bivariate_outliers(X);
        keep = flag == 0;
    end

    subplot(1, length(top3_pre), i); hold on;
    if any(~keep)
        scatter(X(~keep,1), X(~keep,2), 50, [0.75 0.75 0.75], 'filled', ...
            'MarkerFaceAlpha', 0.6);
    end
    scatter(X(keep,1), X(keep,2), 50, [0.3 0.3 0.3], 'filled', ...
        'MarkerFaceAlpha', 0.7);
    p_fit = polyfit(X(keep,1), X(keep,2), 1);
    x_fit = linspace(min(X(keep,1)), max(X(keep,1)), 50);
    plot(x_fit, polyval(p_fit, x_fit), '-', 'Color', [0.78 0.18 0.18], 'LineWidth', 2);

    xlabel(cov_names{iCov}, 'FontSize', 11);
    if i == 1, ylabel('HR effect (bpm)', 'FontSize', 11); end
    title(sprintf('rho=%.2f, p=%.3f (-%d out)', ...
        rvals_pre(iCov), pvals_pre(iCov), n_outliers_pre(iCov)), ...
        'FontSize', 10, 'FontWeight', 'normal');
    set(gca, 'Box', 'off', 'FontSize', 10, 'TickDir', 'out');
end

sgtitle('Top correlations: anticipatory HR effect vs. questionnaires (skipped Spearman)', ...
    'FontSize', 11, 'FontWeight', 'bold');

saveas(gcf, fullfile(out_path_pre, 'HR_questionnaire_scatters_pre_skipped.fig'));
print(gcf,  fullfile(out_path_pre, 'HR_questionnaire_scatters_pre_skipped.png'), '-dpng', '-r300');