%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

%% Time-frequency analysis with a CAUSAL wavelet
%
% WHY THIS EXISTS. A symmetric Morlet wavelet estimates power at time t from
% data on BOTH sides of t. At 1 Hz with 3 cycles that is +/-1432 ms, so
% "pre-stimulus" power within about 1.4 s of the event is estimated partly
% from post-stimulus data. For a paper whose central methodological argument
% is that non-causal filtering manufactures anticipatory effects, estimating
% pre-stimulus power with a non-causal kernel is not defensible.
%
% Three things were considered and rejected:
%
%   Short-time FFT instead of wavelets. Does not help. Resolving frequency f
%   requires roughly 1/f seconds of data whatever the transform - the Gabor
%   limit. An STFT with the same frequency resolution has the same temporal
%   support, just a different window shape.
%
%   Mirror-padding the pre-stimulus window and discarding the pad. Removes the
%   leakage but replaces it with a worse problem: power near 0 ms is then
%   computed from a REFLECTION of that trial's own pre-stimulus data, which is
%   fabricated rather than recorded, and the reflection is trial- and
%   condition-specific so it does not cancel in the contrast.
%
%   Simply raising the low-frequency bound. Helps a lot (support at 3 Hz is
%   477 ms rather than 1432 ms at 1 Hz) but only shrinks the smear; it does
%   not remove it.
%
% WHAT THIS DOES INSTEAD. The wavelet is made CAUSAL: a one-sided Gaussian
% envelope, so the kernel spans only t-3*sigma to t. Power at time t then
% depends on NO sample after t, and forward smearing is zero by construction,
% not merely small. This is the time-frequency counterpart of the
% minimum-phase causal filter already used for the ERP analysis.
%
% Backward reach costs nothing for the pre/post question, so n_cycles is
% raised (4 to 8, from 3 to 7) to recover the frequency resolution that
% one-sidedness would otherwise lose, and the band starts at 3 Hz.
%
% BASELINE WINDOW. Chosen so that its causal support and the tested windows'
% causal support do not overlap, and so that it stays inside the epoch:
%   tested pre-stimulus window starts at -1200 ms, reaching back to -1837 ms
%   at 3 Hz; the baseline ends at -1900 ms, so the two are disjoint.
%   The baseline starts at -2300 ms, reaching back to -2937 ms, inside the
%   -3000 ms epoch.
% This replaces the earlier -2600 to -2000 window, which was fine for the
% symmetric kernel but overlapped the tested window's support here.
%
% Cedric Cannard, September 2026

clear; close all; clc
rng(2026,'twister')
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
addpath(paths.eeglab); eeglab nogui;
data_path   = paths.data;
cd(data_path)
output_path = paths.res_tf_causal;
addpath(paths.ascent); addpath(fullfile(paths.ascent, 'functions'));
global ASCENT_APERIODIC_MODE
ASCENT_APERIODIC_MODE = 'fixed';   % 'fixed' (recommended) or 'knee'
load(fullfile(data_path, 'sInfo.mat'))
addpath(fullfile(paths.robust, 'functions'))
addpath(paths.analysis)   % cluster_correct

% ── PARAMETERS ──────────────────────────────────────────────────────────
fs           = [];   % derived from the data below (true rate is 248 Hz)
% foi          = 1:.5:30;   % above 15 Hz gives bad aperiodic fitting results
foi          = 3:0.5:30;    % 3 Hz floor: below it the kernel is too long to localise
n_cycles     = linspace(4, 8, length(foi)); % raised to offset the one-sided envelope

% ── SUBJECT BOOK-KEEPING ─────────────────────────────────────────────────
subject_list = dir(data_path);
subject_list = subject_list(contains({subject_list.name}, 'sub-'));
subject_list(strcmp({subject_list.name}, 'sub-000')) = [];
subject_list(strcmp({subject_list.name}, 'sub-005')) = [];
subject_list(strcmp({subject_list.name}, 'sub-009')) = [];
% subject_list(strcmp({subject_list.name}, 'sub-011')) = [];
nSub = length(subject_list);

% ── CHANNEL ORDER ───────────────────────────────────────────────────────
new_order = {'Fp1','Fp2','F1','F2','CZ','C3','C4','PZ','P3','P4','O1','O2'};

% ── COMPUTE RAW WAVELET POWER FOR ALL SUBJECTS ────────────────────────────────────────
% Do the expensive wavelet computation once, store channel-averaged
% single-trial raw power. Normalization applied separately per mode later.
%
% RAW_CRASH{iSub}   : [nFreq x nTime x nTrials]  raw power, channel-averaged
% RAW_NOCRASH{iSub} : [nFreq x nTime x nTrials]

[RAW_CRASH, RAW_NOCRASH] = deal(cell(nSub, 1));
times_ref = [];
chanlocs  = [];

fprintf('=== Computing wavelet power ===\n')
for iSub = 1:nSub
    fprintf('Subject %g/%g\n', iSub, nSub)

    subFolder = fullfile(data_path, subject_list(iSub).name);
    data      = load(fullfile(subFolder, 'ERP_EEG_new.mat'));

    if strcmpi(extractAfter(subFolder, data_path), '\sub-011')
        data2 = load(fullfile(subFolder, 'ERP_EEG2_new.mat'));
        assert(~isequal(data.crash.data, data2.crash.data), ...
            'sub-011 files identical - run fix_sub011_erp_export.m first!')
        data.crash.data    = cat(3, data.crash.data,    data2.crash.data);
        data.no_crash.data = cat(3, data.no_crash.data, data2.no_crash.data);
    end

    [~, idx] = ismember(new_order, {data.chanlocs.labels});
    if isempty(chanlocs), chanlocs = data.chanlocs(idx); end
    crash_ep   = data.crash.data(idx, :, :);
    nocrash_ep = data.no_crash.data(idx, :, :);
    times      = data.crash.times;
    if isempty(times_ref), times_ref = times; end
    if isempty(fs), fs = 1000/median(diff(times)); fprintf('Sampling rate: %.3f Hz\n', fs); end

    % Raw power per channel [nChan x nFreq x nTime x nTrials] and
    % averaged across channels
    rp_crash   = compute_raw_power(crash_ep,   foi, n_cycles, fs);
    rp_nocrash = compute_raw_power(nocrash_ep, foi, n_cycles, fs);

    % store for group analysis
    RAW_CRASH{iSub}   = rp_crash;
    RAW_NOCRASH{iSub} = rp_nocrash;

    fprintf('RAW_CRASH{%d} size: %s\n', iSub, mat2str(size(RAW_CRASH{iSub})))
    fprintf('RAW_NOCRASH{%d} size: %s\n', iSub, mat2str(size(RAW_NOCRASH{iSub})))

end
times = times_ref;
fprintf('Wavelet computation done. Subjects: %g\n', nSub)


%% ── RUN GLMs AND STATS ──────────────────────────────────────────────────
% TWO NORMALIZATION MODE:
%   1) classic baseline correction (in dB)
%   2) aperiodic component correction (in dB)

% Baseline window for the Alday regressor. Chosen empirically by
% check_tf_baseline_windows.m, which measures the condition difference INSIDE
% each candidate window (the only quantity that can bias the condition
% coefficient). Of four candidates this was the cleanest: max |d| = 0.31
% against 0.57 for the adjacent -1500 to -1200 window and 0.35 for the ERP
% analysis's -3000 to -2000, which sits in wavelet mirror-padding here.
% It fits inside the existing -3000 to +3000 ms epochs, so no re-epoching.
baseline_win = [-2300 -1900];               % ms; causally disjoint from both tested windows
% Reported in this order. 'none' is primary: no baseline correction at all,
% so nothing is assumed about how the aperiodic background behaves over time
% (Gyurkovics et al. show it does not hold still). 'baseline' and
% 'aperiodic' are robustness checks, each with its own assumption.
% Reported in this order, most to least assumption-laden in reverse:
%   none        PRIMARY. No normalisation. Nothing is assumed about the
%               aperiodic background; the condition contrast removes it.
%   glmbaseline Alday (2019) applied to power. Per-trial baseline power is
%               mean-centred and entered as a THIRD design column instead of
%               being divided out, so its weight is estimated rather than
%               fixed at -1 and its noise is not injected into every trial.
%
% An aperiodic (1/f subtraction) mode exists in normalize_tf and is NOT run.
% It was dropped deliberately: the fit is static while the aperiodic
% background is not (Gyurkovics et al.), it is poorly constrained over a
% 1-15 Hz range where a knee is not identifiable, and the cluster extents
% already span the whole analysed band, so "broadband" is read off the
% clusters rather than from a decomposition. A time-resolved fit (SPRiNT;
% Wilson et al., 2022) is the principled version and needs windows longer
% than the 1200 ms tested here.
norm_modes  = {'none' 'glmbaseline'};   % pre and post tested separately, as registered
SEED        = 2026;   % re-seeded per frequency in the glmbaseline mode
optim       = 'WLS';
weight      = 'Huber';
nPerm       = 1000;
mcc_type    = 2;
merge_clust = 10;
es          = 'd';

% ── CAUSAL SUPPORT, FOR THE RECORD ───────────────────────────────────────
supp_ms = 3000 * (n_cycles(:) ./ (2*pi*foi(:)));
fprintf('\nCausal support (backwards only, forward reach is zero):\n');
for k = [1 5 15 numel(foi)]
    fprintf('  %5.1f Hz : %6.0f ms back\n', foi(k), supp_ms(k));
end
fprintf('  pre-stimulus window starts at -1200 ms, reaching back to %.0f ms\n', -1200-supp_ms(1));
fprintf('  Alday baseline ends at %g ms -> disjoint: %d\n\n', ...
    baseline_win(2), (-1200-supp_ms(1)) > baseline_win(2));

% ── PER-TRIAL BASELINE POWER, FOR THE ALDAY DESIGN COLUMN ────────────────
% [nFreq x nTrials] per subject, in dB, mean-centred WITHIN subject and
% frequency (mirrors run_final_EEG_alday.m, which centres within subject and
% channel). Computed from RAW power so it is independent of whichever
% normalisation mode is running.
bl_idx = times >= baseline_win(1) & times <= baseline_win(2);
fprintf('\nAlday baseline window %g to %g ms (%d samples)\n', baseline_win, sum(bl_idx));
[BL_CRASH, BL_NOCRASH] = deal(cell(nSub, 1));
for iSub = 1:nSub
    bc = squeeze(mean(10*log10(RAW_CRASH{iSub}(:, bl_idx, :)), 2));    % [nFreq x nTrials]
    bn = squeeze(mean(10*log10(RAW_NOCRASH{iSub}(:, bl_idx, :)), 2));
    mu = mean([bc bn], 2);                                            % centre per frequency
    BL_CRASH{iSub}   = bc - mu;
    BL_NOCRASH{iSub} = bn - mu;
end

% Does the baseline window itself differ by condition? If not, the baseline
% regressor is pure variance reduction and cannot absorb the condition effect.
bl_d = nan(numel(foi), 1);
for f = 1:numel(foi)
    per_sub = arrayfun(@(sIdx) mean(BL_CRASH{sIdx}(f,:)) - mean(BL_NOCRASH{sIdx}(f,:)), 1:nSub);
    bl_d(f) = mean(per_sub) / std(per_sub);
end
fprintf('Condition difference IN THE BASELINE WINDOW, max |d| = %.3f over %g-%g Hz\n', ...
    max(abs(bl_d)), foi(1), foi(end));
fprintf('  (small values => the baseline regressor is not collinear with condition)\n\n');

for norm_mode = norm_modes
    mode = norm_mode{1};
    fprintf('\n=== Normalization mode: %s ===\n', mode)

    % Step 3-5: normalize raw power per subject
    [TF_CRASH, TF_NOCRASH] = deal(cell(nSub, 1));
    for iSub = 1:nSub
        fprintf('  Normalizing subject %g/%g\n', iSub, nSub)
        [TF_CRASH{iSub}, TF_NOCRASH{iSub}] = normalize_tf(RAW_CRASH{iSub}, RAW_NOCRASH{iSub}, ...
            foi, mode, baseline_win, times);
    end

    % ── DESIGN MATRIX ────────────────────────────────────────────────────
    n_crash       = cellfun(@(x) size(x,3), TF_CRASH);
    n_nocrash     = cellfun(@(x) size(x,3), TF_NOCRASH);
    subj_idx      = [repelem(1:nSub, n_crash)'; repelem(1:nSub, n_nocrash)'];
    condition_col = [ones(sum(n_crash),1); zeros(sum(n_nocrash),1)];
    X             = [ones(length(condition_col),1), condition_col];
    bl_all        = [cat(2, BL_CRASH{:})'; cat(2, BL_NOCRASH{:})'];   % [nTrials x nFreq]

    fprintf('  Total trials: %d (crash=%d, nocrash=%d)\n', ...
        length(condition_col), sum(n_crash), sum(n_nocrash));

    % ── POST-STIMULUS GLM ─────────────────────────────────────────────────
    tlims = [0 1200];
    alpha = 0.05;

    out_path = fullfile(output_path, mode, 'post-stim'); mkdir(out_path)
    [tvals, pvals, tvals_H0, pvals_H0, time, CRASH_AVG, NOCRASH_AVG] = ...
        run_tf_glm(TF_CRASH, TF_NOCRASH, times, tlims, nSub, nPerm, ...
        X, condition_col, subj_idx, optim, weight, mode, bl_all, SEED);
    mask = compute_mcc_tf(tvals, pvals, tvals_H0, mcc_type, alpha, nSub);
    save(fullfile(out_path, 'TF_stats_post.mat'), ...
        'tvals', 'pvals', 'mask', 'time', 'foi', 'CRASH_AVG', 'NOCRASH_AVG', 'mode');
    if any(mask, 'all')
        [mask_clusters, summary_tbl] = pull_clusters_tf(mask, tvals, time, foi, ...
            merge_clust, es, nSub);
        plot_tf_grandavg(time, foi, CRASH_AVG, NOCRASH_AVG, tvals, mask, ...
            mask_clusters, summary_tbl, mcc_type, mode, out_path);
        writetable(summary_tbl, fullfile(out_path, sprintf('TF_clusters_corr-%d.csv', mcc_type)), ...
            'WriteMode', 'overwrite');
        plot_tf_clusters(mask_clusters, summary_tbl, tvals, time, foi, mcc_type, out_path);
    else
        fprintf('  No significant TF clusters (post-stim, %s).\n', mode)
        plot_tf_grandavg(time, foi, CRASH_AVG, NOCRASH_AVG, tvals, mask, ...
            {}, table(), mcc_type, mode, out_path);
    end

    % ── PRE-STIMULUS GLM ──────────────────────────────────────────────────
    tlims = [-1200 -1];
    alpha = 0.05;

    out_path = fullfile(output_path, mode, 'pre-stim'); mkdir(out_path)
    [tvals, pvals, tvals_H0, pvals_H0, time, CRASH_AVG, NOCRASH_AVG] = ...
        run_tf_glm(TF_CRASH, TF_NOCRASH, times, tlims, nSub, nPerm, ...
        X, condition_col, subj_idx, optim, weight, mode, bl_all, SEED);
    mask = compute_mcc_tf(tvals, pvals, tvals_H0, mcc_type, alpha, nSub);
    save(fullfile(out_path, 'TF_stats_pre.mat'), ...
        'tvals', 'pvals', 'mask', 'time', 'foi', 'CRASH_AVG', 'NOCRASH_AVG', 'mode');
    if any(mask, 'all')
        [mask_clusters, summary_tbl] = pull_clusters_tf(mask, tvals, time, foi, ...
            merge_clust, es, nSub);
        plot_tf_grandavg(time, foi, CRASH_AVG, NOCRASH_AVG, tvals, mask, ...
            mask_clusters, summary_tbl, mcc_type, mode, out_path);
        writetable(summary_tbl, fullfile(out_path, sprintf('TF_clusters_corr-%d.csv', mcc_type)));
        plot_tf_clusters(mask_clusters, summary_tbl, tvals, time, foi, mcc_type, out_path);

    else
        fprintf('  No significant TF clusters (pre-stim, %s).\n', mode)
        plot_tf_grandavg(time, foi, CRASH_AVG, NOCRASH_AVG, tvals, mask, ...
            {}, table(), mcc_type, mode, out_path);
    end
end  % norm_mode loop


%% ══════════════════════════════════════════════════════════════════════
%%  LOCAL FUNCTIONS
% ══════════════════════════════════════════════════════════════════════

% ── STEP 1+2: RAW POWER PER CHANNEL, THEN CHANNEL AVERAGE ────────────────
function raw_power_avg = compute_raw_power(epoch_data, foi, n_cycles, fs)
% epoch_data    : [nChan x nTime x nTrials]
% Returns       : [nFreq x nTime x nTrials]  trimmed-mean across channels

[nChan, nTime, nTrials] = size(epoch_data);
nFreq = length(foi);

% % Diagnostic padding and freqs
% fprintf('nTime: %d\n', nTime)
% for iFreq = 1:nFreq
%     f       = foi(iFreq);
%     sigma_t = n_cycles(iFreq) / (2 * pi * f);
%     t_win   = -3*sigma_t : 1/fs : 3*sigma_t;
%     pad_len = ceil(length(t_win) / 2);
%     fprintf('foi=%.1f Hz, wavelet_len=%d, pad_len=%d\n', f, length(t_win), pad_len)
% end

% Pre-compute CAUSAL wavelets. tau runs 0 to 3*sigma BACKWARDS in time, so
% h(1) is the weight on the current sample and h(end) the weight on the sample
% 3*sigma in the past. Nothing after t contributes to power at t.
wavelets = cell(nFreq, 1);
pad_lens = zeros(nFreq, 1);
for iFreq = 1:nFreq
    f       = foi(iFreq);
    sigma_t = n_cycles(iFreq) / (2 * pi * f);
    tau     = (0 : ceil(3*sigma_t*fs)) / fs;          % lags into the past, s
    A       = 1 / (sigma_t * sqrt(2*pi));
    wavelets{iFreq} = A * exp(-(tau.^2)/(2*sigma_t^2)) .* exp(-2i*pi*f*tau);
    pad_lens(iFreq) = length(wavelets{iFreq});        % left-side padding only
end

% Raw power per channel [nChan x nFreq x nTime x nTrials]
raw_power = nan(nChan, nFreq, nTime, nTrials);
for iChan = 1:nChan
    for iTrial = 1:nTrials
        sig = double(epoch_data(iChan, :, iTrial));
        for iFreq = 1:nFreq
            % LEFT padding only. The kernel never looks forward, so the end of
            % the epoch needs no pad; the mirrored lead-in only affects the
            % first ~3*sigma of the epoch, which is far from either tested
            % window.
            pad_len    = pad_lens(iFreq);
            pad_start  = sig(min(pad_len,end):-1:1);
            sig_padded = [pad_start, sig];

            % filter() is causal by definition: y(k) = sum_j h(j) x(k-j+1)
            y          = filter(wavelets{iFreq}, 1, sig_padded);
            conv_trim  = y(pad_len+1 : pad_len+nTime);

            raw_power(iChan, iFreq, :, iTrial) = abs(conv_trim).^2;
        end
    end
end
% fprintf('raw_power size before squeeze: %s\n', mat2str(size(raw_power)))
% fprintf('before squeeze: %s\n', mat2str(size(trimmean(raw_power, 20, 1))))
% raw_power_avg = squeeze(trimmean(raw_power, 20, 1));
% fprintf('after squeeze: %s\n', mat2str(size(raw_power_avg)))

% Collapse channels in power space (dim 1)
% raw_power_avg = squeeze(mean(raw_power, 1));  % [nFreq x nTime x nTrials]
raw_power_avg = squeeze(trimmean(raw_power, 20, 1));  % [nFreq x nTime x nTrials]
end


% ── STEPS 3-5: NORMALIZE PER SUBJECT ─────────────────────────────────────
function [TF_crash, TF_nocrash] = normalize_tf(raw_crash, raw_nocrash, foi, mode, baseline_win, times)
% raw_crash   : [nFreq x nTime x nTrials]  channel-averaged raw power
% raw_nocrash : [nFreq x nTime x nTrials]
% Returns normalized TF with same dimensions

freq_range  = [foi(1) foi(end)];
% freq_range  = [0.5 15];
nTrials_c   = size(raw_crash,   3);
nTrials_nc  = size(raw_nocrash, 3);

switch mode

    case {'none', 'glmbaseline'}

        % PRIMARY ('none'), and the data side of 'glmbaseline': in the Alday
        % variant the baseline enters the DESIGN MATRIX, not the data, so the
        % power handed to the GLM is the same uncorrected dB in both cases.
        % Raw wavelet power to dB, no normalisation of any kind.
        % Every trial keeps its own aperiodic background; the condition
        % contrast is what removes it, since both conditions come from the
        % same participants and the same sessions. Nothing here assumes the
        % background is stationary in time, which is the assumption the
        % baseline and aperiodic modes each make in a different way.
        TF_crash   = 10 * log10(raw_crash);
        TF_nocrash = 10 * log10(raw_nocrash);

    case 'baseline'

        % Gyurkovics-safe: divide raw power by baseline raw power, then dB.
        % Never subtract dB values directly.
        TF_crash   = nan(size(raw_crash));
        TF_nocrash = nan(size(raw_nocrash));

        if ~any(isnan(baseline_win))
            % Baseline correction: divide raw power by baseline, then dB
            bl_idx = times >= baseline_win(1) & times <= baseline_win(2);
            if sum(bl_idx) < 2, error('Baseline window too short.'); end
            for iTrial = 1:nTrials_c
                pwr    = raw_crash(:, :, iTrial);
                bl_pwr = mean(pwr(:, bl_idx), 2);
                bl_pwr(bl_pwr <= 0) = nan;
                TF_crash(:, :, iTrial) = 10 * log10(pwr ./ bl_pwr);
            end
            for iTrial = 1:nTrials_nc
                pwr    = raw_nocrash(:, :, iTrial);
                bl_pwr = mean(pwr(:, bl_idx), 2);
                bl_pwr(bl_pwr <= 0) = nan;
                TF_nocrash(:, :, iTrial) = 10 * log10(pwr ./ bl_pwr);
            end
        else
            % No baseline correction: just convert to dB
            for iTrial = 1:nTrials_c
                TF_crash(:, :, iTrial) = 10 * log10(raw_crash(:, :, iTrial));
            end
            for iTrial = 1:nTrials_nc
                TF_nocrash(:, :, iTrial) = 10 * log10(raw_nocrash(:, :, iTrial));
            end
        end

    case 'aperiodic'
        % Step 3: trial-average per condition for stable specparam fit
        avg_crash   = trimmean(raw_crash,   20, 3);  % [nFreq x nTime]
        avg_nocrash = trimmean(raw_nocrash, 20, 3);

        % Step 4: fit specparam on full time-averaged spectrum [1 x nFreq]
        psd_crash   = mean(avg_crash,   2)';
        psd_nocrash = mean(avg_nocrash, 2)';

        % % using only over pre-stimulus baseline period for fitting
        % bl_idx_ap = times >= -1500 & times <= -100;  % pre-stim only
        % psd_crash   = mean(avg_crash(:, bl_idx_ap),   2)';
        % psd_nocrash = mean(avg_nocrash(:, bl_idx_ap), 2)';

        fm_crash   = fit_aperiodic(foi, psd_crash,   freq_range);
        fm_nocrash = fit_aperiodic(foi, psd_nocrash, freq_range);

        % Reconstruct aperiodic model in dB
        ap_crash   = aperiodic_model(fm_crash,   foi);
        ap_nocrash = aperiodic_model(fm_nocrash, foi);
        log_ap_crash   = 10 * log10(ap_crash);
        log_ap_nocrash = 10 * log10(ap_nocrash);

        % % Diagnostic
        % log_psd_crash   = 10 * log10(psd_crash(:));
        % log_psd_nocrash = 10 * log10(psd_nocrash(:));
        % fprintf('    Corrected PSD crash range:   %.2f to %.2f dB\n', ...
        %     min(log_psd_crash - log_ap_crash), max(log_psd_crash - log_ap_crash))
        % fprintf('    Corrected PSD nocrash range: %.2f to %.2f dB\n', ...
        %     min(log_psd_nocrash - log_ap_nocrash), max(log_psd_nocrash - log_ap_nocrash))

        % Step 5: subtract aperiodic in dB from each trial
        TF_crash   = nan(size(raw_crash));
        TF_nocrash = nan(size(raw_nocrash));
        for iTrial = 1:nTrials_c
            raw_db = 10 * log10(raw_crash(:, :, iTrial));
            TF_crash(:, :, iTrial) = raw_db - log_ap_crash;
        end
        for iTrial = 1:nTrials_nc
            raw_db = 10 * log10(raw_nocrash(:, :, iTrial));
            TF_nocrash(:, :, iTrial) = raw_db - log_ap_nocrash;
        end

    otherwise
        error('Unknown mode: %s', mode)
end
end


% ── FIT SPECPARAM AND RETURN fm STRUCT ───────────────────────────────────
function fm = fit_aperiodic(foi, psd, freq_range)
% Fit the aperiodic component with Ascent's pure-MATLAB FOOOF reimplementation.
% psd : [1 x nFreq] raw linear power.
global ASCENT_APERIODIC_MODE
mode_ap = ASCENT_APERIODIC_MODE;
if isempty(mode_ap), mode_ap = 'fixed'; end

if any(psd <= 0) || any(~isfinite(psd))
    error('Zero, negative or non-finite power in spectrum, cannot fit aperiodic model.')
end

[expo, offs, info] = compute_AperiodicFit(foi(:)', psd(:)', ...
    'FreqRange',       freq_range, ...
    'AperiodicMode',   mode_ap, ...
    'MaxPeaks',        4, ...
    'MinPeakHeight',   0.1, ...
    'PeakThreshold',   2.0, ...
    'PeakWidthLimits', [0.5 6], ...
    'Parallel',        false, ...
    'Progress',        false);

% One 'channel' only. In compute_AperiodicFit, ap_fit is a per-channel CELL,
% r_squared/error are numeric ARRAYS, and freqs_used is a single shared vector.
fm.ap_fit_log10 = info.ap_fit{1};     % [nFit x 1], log10 power
fm.freqs_used   = info.freqs_used(:); % [nFit x 1], Hz (linear, not log)
fm.r_squared    = info.r_squared(1);
fm.error        = info.error(1);
fm.exponent     = expo(1);
fm.offset       = offs(1);
fm.mode         = mode_ap;
fm.freqs        = foi;

if fm.r_squared < 0.8
    warning('Poor aperiodic fit: R2=%.2f. Results may be unreliable.', fm.r_squared)
end
fprintf('    aperiodic fit (%s, Ascent): R2=%.3f, exponent=%.3f\n', ...
    mode_ap, fm.r_squared, fm.exponent);
end


% ── RECONSTRUCT APERIODIC MODEL AT foi ───────────────────────────────────
function ap_model = aperiodic_model(fm, foi)
% Returns [nFreq x 1] aperiodic power in LINEAR space, so the caller's
% 10*log10() conversion is unchanged. Uses the fitted spectrum returned by
% compute_AperiodicFit, which is correct for both 'fixed' and 'knee'.
f_used = fm.freqs_used(:);
ap_log = fm.ap_fit_log10(:);
if numel(f_used) == numel(foi) && all(abs(f_used - foi(:)) < 1e-9)
    ap_log_full = ap_log;
else
    % fit range narrower than foi: interpolate, extrapolate at the edges
    ap_log_full = interp1(f_used, ap_log, foi(:), 'linear', 'extrap');
end
ap_model = 10.^ap_log_full;
end


% ── RUN HIERARCHICAL GLM ─────────────────────────────────────────────────
function [tvals, pvals, tvals_H0, pvals_H0, time, CRASH_AVG, NOCRASH_AVG] = ...
    run_tf_glm(TF_CRASH, TF_NOCRASH, times, tlims, nSub, nPerm, ...
    X, condition_col, subj_idx, optim, weight, mode, bl_all, SEED)
% TF_CRASH{iSub} : [nFreq x nTime x nTrials]
% Returns tvals  : [nFreq x nTime]
%         tvals_H0 : [nFreq x nTime x nPerm]

time_idx = times >= tlims(1) & times <= tlims(2);
time     = times(time_idx);

crash_cells   = cellfun(@(x) x(:,time_idx,:), TF_CRASH,   'UniformOutput', false);
nocrash_cells = cellfun(@(x) x(:,time_idx,:), TF_NOCRASH, 'UniformOutput', false);
Y_crash   = cat(3, crash_cells{:});
Y_nocrash = cat(3, nocrash_cells{:});
Y_all     = cat(3, Y_crash, Y_nocrash);

% Subject-mean for plotting
% crash_means   = cellfun(@(x) mean(x(:,time_idx,:), 3), TF_CRASH,   'UniformOutput', false);
% nocrash_means = cellfun(@(x) mean(x(:,time_idx,:), 3), TF_NOCRASH, 'UniformOutput', false);
% CRASH_AVG   = mean(cat(3, crash_means{:}),   3);
% NOCRASH_AVG = mean(cat(3, nocrash_means{:}), 3);
crash_means   = cellfun(@(x) trimmean(x(:,time_idx,:), 20, 3), TF_CRASH,   'UniformOutput', false);
nocrash_means = cellfun(@(x) trimmean(x(:,time_idx,:), 20, 3), TF_NOCRASH, 'UniformOutput', false);
CRASH_AVG   = trimmean(cat(3, crash_means{:}),  20, 3);
NOCRASH_AVG = trimmean(cat(3, nocrash_means{:}), 20, 3);

fprintf('  GLM: %d trials (crash=%d, nocrash=%d), [%d freqs x %d times]\n', ...
    size(Y_all,3), size(Y_crash,3), size(Y_nocrash,3), size(Y_all,1), size(Y_all,2));

if nargin >= 12 && strcmp(mode, 'glmbaseline')
    % ALDAY VARIANT. Baseline power is frequency-specific, but the Level-1
    % design matrix is shared across the third dimension, so each frequency
    % has to be fitted with its own design - the same reason
    % run_final_EEG_alday.m fits each channel separately.
    %
    % The RNG is re-seeded identically before every frequency so that all
    % frequencies see the SAME permutations. Otherwise the frequency-time
    % structure of the null is destroyed and the cluster correction becomes
    % anti-conservative.
    nFreq = size(Y_all, 1);
    nTime = size(Y_all, 2);
    tvals    = nan(nFreq, nTime);
    pvals    = nan(nFreq, nTime);
    tvals_H0 = nan(nFreq, nTime, nPerm);
    pvals_H0 = nan(nFreq, nTime, nPerm);
    for f = 1:nFreq
        Xf = [ones(numel(condition_col),1), condition_col, bl_all(:,f)];
        rng(SEED, 'twister');
        % Freedman-Lane: naive label permutation is invalid once the design
        % carries a nuisance covariate (see run_stats_permutation_glm_fl).
        [~, tv, tvH0, ~, pv, pvH0] = run_stats_permutation_glm_fl( ...
            Y_all(f,:,:), Xf, condition_col, nSub, nPerm, ...
            'Subjects', subj_idx, 'Method', optim, 'WeightType', weight, ...
            'CondCol', 2, 'Progress', false);
        tvals(f,:)      = tv;
        pvals(f,:)      = pv;
        tvals_H0(f,:,:) = tvH0;
        pvals_H0(f,:,:) = pvH0;
        fprintf('   frequency %2d/%d done\n', f, nFreq);
    end
else
    [~, tvals, tvals_H0, ~, pvals, pvals_H0] = run_stats_permutation_glm_hierarchical( ...
        Y_all, X, condition_col, nSub, nPerm, ...
        'Subjects', subj_idx, 'Method', optim, 'WeightType', weight, 'Progress', true);
end
end


% ── CLUSTER MCC ──────────────────────────────────────────────────────────
function mask = compute_mcc_tf(tvals, pvals, tvals_H0, mcc_type, alpha, nSub)

switch mcc_type
    case 0
        mask = pvals < alpha;

    case 1
        max_H0 = squeeze(max(max(abs(tvals_H0), [], 1), [], 2));
        thresh  = prctile(max_H0, (1-alpha)*100);
        mask    = abs(tvals) > thresh;

    case 2
    % Cluser-size
    nPerm = size(tvals_H0, 3);
    df    = nSub - 1;

    % Fixed t-threshold from t-distribution (not data-driven, avoids circularity)
    uncorr_thresh = tinv(1 - alpha/2, df);
    % uncorr_thresh = tinv(1 - 0.01/2, df);  % t=2.92 for df=16, more conservative

    % Build H0 cluster size distribution
    clust_H0 = zeros(1, nPerm);
    for iPerm = 1:nPerm
        perm_map = abs(squeeze(tvals_H0(:,:,iPerm)));
        CC       = bwconncomp(perm_map > uncorr_thresh);
        sizes    = cellfun(@numel, CC.PixelIdxList);
        if ~isempty(sizes), clust_H0(iPerm) = max(sizes); end
    end
    thresh_clust = prctile(clust_H0, (1-alpha)*100);
    % thresh_clust = prctile(clust_H0, (1 - alpha/2)*100);  % more conservative: 97.5th instead of 95th

    % Apply to observed map using p-values < alpha for initial thresholding
    CC   = bwconncomp(pvals < alpha & abs(tvals) > uncorr_thresh);
    mask = false(size(tvals));
    for ic = 1:CC.NumObjects
        if numel(CC.PixelIdxList{ic}) >= thresh_clust
            mask(CC.PixelIdxList{ic}) = true;
        end
    end
    
    % % % Cluster-mass (LIMO-style)
    % nPerm = size(tvals_H0, 3);
    % df    = nSub - 1;
    % uncorr_thresh = tinv(1 - alpha/2, df);
    % 
    % % Build H0 cluster mass distribution (sum of t-values, not size)
    % clust_H0 = zeros(1, nPerm);
    % for iPerm = 1:nPerm
    %     perm_map = squeeze(tvals_H0(:,:,iPerm));
    %     CC       = bwconncomp(abs(perm_map) > uncorr_thresh);
    %     if CC.NumObjects > 0
    %         masses = cellfun(@(idx) sum(abs(perm_map(idx))), CC.PixelIdxList);
    %         clust_H0(iPerm) = max(masses);
    %     end
    % end
    % thresh_clust = prctile(clust_H0, (1-alpha)*100);
    % 
    % % Apply to observed map using cluster mass
    % CC   = bwconncomp(pvals < alpha & abs(tvals) > uncorr_thresh);
    % mask = false(size(tvals));
    % for ic = 1:CC.NumObjects
    %     cluster_mass = sum(abs(tvals(CC.PixelIdxList{ic})));
    %     if cluster_mass >= thresh_clust
    %         mask(CC.PixelIdxList{ic}) = true;
    %     end
    % end

    otherwise
        warning('mcc_type %d not implemented, using uncorrected.', mcc_type)
        mask = pvals < alpha;
end
end
