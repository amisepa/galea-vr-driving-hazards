clear; close all; clc
eeglab; close
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
codepath = paths.root;
datapath = paths.data;
outputpath = datapath;
addpath(fullfile(codepath,'pipeline','functions'))
cd(datapath)

%%%%%%%%%%%%%%%%%%%%%%%%%%%% PARAMETERS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
causal_filt = true;      % false (noncausal zero-phase filter) and true (causal min-phase filter; preserves causality + doesn't introduce group delays)
filt_cutoffs = [0.5 3]; % filter cutoff frequencies (in Hz)
detect_mode = 'valleys'; % detect 'valleys' (default) or 'peaks' for heartbeats
epoch_lims = [-5 5];   % epoch window in seconds
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

load(fullfile(datapath, 'sInfo_ppg.mat'))
fprintf('Last subject processed: %g\n', sInfo(end).subject)

% Import data
[~, ~, ~, PPG] = galea_import();  
sub_num = regexp(regexprep(PPG.filepath, ['\' filesep '$'], ''), 'sub-(\d+)$', 'tokens');
sub_num = str2double(sub_num{:}{:});


% Trim period before 1st event and after last event to remove garbage
% signal
PPG = pop_select(PPG, 'nopoint', [0 PPG.event(1).latency - PPG.srate*1]); % 1 second
PPG = pop_select(PPG, 'nopoint', [PPG.event(end).latency + PPG.srate*1 PPG.pnts]);

% Rename events
disp("")
PPG = galea_rename_events(PPG);
if length(PPG.event) < 80
    error("less than 80 trials total at import. This file won't have enough trials (40 in each condition) and needs to be skipped. ")
end

% Create new sInfo to store preprocessing info
if sub_num == 1
    sInfo = [];  % start new sInfo file
    warning("Subject 1 selected. Overwriting sInfo!!!")
end
sInfo(end+1).subject = sub_num;  % returns '002' as a string
sInfo(end).filepath = PPG.filepath;
sInfo(end).filename = PPG.filename;
sInfo(end).file_length = PPG.xmax / 60;
sInfo(end).data_type = 'PPG';
sInfo(end).events = PPG.event;


% % Calculate SNR on cleaned NN time series (INCORRECT AFTER LOWPASS FILTER)
disp("calculating SNR metrics...");
for iChan = 1:PPG.nbchan
    [metrics, seg_idx] = calc_signal_features(PPG.data(iChan,:), 'ppg', PPG.srate, 4, true);
    flat(iChan) = (sum(metrics.flat) / length(metrics.flat)) * 100;
    snr(iChan) = round(median(metrics.pSNR),1);
    snr2(iChan) = round(median(metrics.tSNR),1);
    snr3(iChan) = round(median(metrics.SNR1),1);
end
T = table((1:PPG.nbchan)', snr', snr2', snr3', ...
    'VariableNames', {'Channel', 'pSNR', 'tSNR', 'SNR1'});
disp(T)
sInfo(end).SNR = snr;
sInfo(end).SNR2 = snr3;
sInfo(end).flat = flat;

if snr(1)<1 && snr(2)<1
    save(fullfile(datapath, 'sInfo_ppg.mat'), 'sInfo')
    pop_eegplot(PPG,1,1,1);
    error("Subject: %g SNR too low on both channels ! Bad file", sub_num)
else
    close(gcf);  % close diagnostics figure
end
[~, bestChan] = max(snr);
fprintf('Best PPG channel: %s (#%g) \n', PPG.chanlocs(bestChan).labels, bestChan)
PPG = pop_select(PPG, 'channel', {PPG.chanlocs(bestChan).labels});
sInfo(end).best_chan =  PPG.chanlocs.labels;

% Filter signal
PPG = pop_eegfiltnew(PPG,'locutoff',filt_cutoffs(1),'minphase', causal_filt);      % final data for ERP analysis
PPG = pop_eegfiltnew(PPG,'hicutoff',filt_cutoffs(2),'minphase', causal_filt);      % final data for ERP analysis


% Detect RR intervals and clean them using the Brainbeats EEGLAB plugin
params.fs = PPG.srate; params.heart_signal = 'ppg'; 
% params.ppg_detect_mode
params.ppg_bandpass = 0;
% params.ppg_height_method = 'mad';
[rr, rr_t, rPeaks, sig, sig_t] = get_RR(PPG.data, PPG.times, params);
[nn, nn_t, nPeaks, idx_bad] = clean_rr_legacy(rr_t, rr, rPeaks, params);
% [nn, nn_t, nPeaks, idx_bad, idx_interp] = clean_rr(rr_t, rr, sig(rPeaks), rPeaks, ...
%     'interpolate_missing', true, 'ecg_signal', sig, 'sig_t', sig_t, 'fs', PPG.srate );
plot_NN(sig_t, sig, rr_t, rr, rPeaks, nn_t, nn, nPeaks, params.heart_signal)
% print(gcf, fullfile(PPG.filepath, 'PPG_RR_NN.png'), '-dpng','-r300');
exportapp(gcf, fullfile(PPG.filepath, 'PPG_RR_NN.png'))
savefig(gcf, fullfile(PPG.filepath, 'PPG_RR_NN.fig'));
sInfo(end).idx_bad = idx_bad;
% sInfo(end).idx_interp = idx_interp;

% Heart Rate
hr = 60 ./ nn;

% % Mild smoothing of HR using Gaussian-weighted moving average (zero-phase)
% win_s   = 3;                          % smoothing window in seconds
% win_samp = max(3, round(win_s * median(diff(nn_t), 'omitnan')^-1));
% if mod(win_samp, 2) == 0, win_samp = win_samp + 1; end  % force odd
% w       = gausswin(win_samp);
% w       = w / sum(w);
% hr_smooth = filtfilt(w, 1, hr);

% hr_smooth = hr_smooth - mean(hr_smooth);
% eegplot(hr_smooth', 'srate', round(1/median(diff(nn_t), 'omitnan'),2), 'spacing', 30, 'winlength', 30 );

% figure('color','w');
% scrollplot( ...
%     {nn_t, hr,        'color',[0, 0.4470, 0.7410], 'LineWidth', 1.5}, {'X'}, 30, ...
%     {nn_t, hr_smooth, 'color', [0.4660, 0.6740, 0.1880],     'LineWidth', 1.5});
% ylabel('HR (bpm)');
% legend('raw HR', 'smoothed HR');

% ERP
event_labels = {PPG.event.type};
crash_idx = strcmpi(event_labels, 'tire_pop');
crash_timestamps = [PPG.event(crash_idx).latency] ./ PPG.srate; % in s
nocrash_idx = strcmpi(event_labels, 'no_tire_pop');
nocrash_timestamps = [PPG.event(~nocrash_idx).latency] ./ PPG.srate; % in s
sInfo(end).events = event_labels;

% Epoch CRASH condition
crash = [];
for iTrial = 1:length(crash_timestamps)
    trial_epoch = crash_timestamps(iTrial)+epoch_lims(1):crash_timestamps(iTrial)+epoch_lims(2); % timestamps for this epoch
    trial_idx = interp1(nn_t, 1:length(nn_t), trial_epoch, 'nearest', 'extrap'); % sample index for this epoch
    crash(:,iTrial) = hr(trial_idx); % HR values for this epoch
end
fprintf('Number of crash trials: %d\n', length(crash_timestamps));

% Deduplicate no-crash events closer than min_trial_dur
min_trial_dur = 5;  % seconds - adjust to your trial design
keep = [true, diff(sort(nocrash_timestamps)) > min_trial_dur];
nocrash_timestamps = nocrash_timestamps(keep);
fprintf('No-crash trials after deduplication: %d\n', length(nocrash_timestamps));

% Remove no-crash events that coincide with crash events
min_sep = 0.01;  % seconds tolerance for "same event"
is_also_crash = any(abs(nocrash_timestamps - crash_timestamps') < min_sep, 1);
nocrash_timestamps(is_also_crash) = [];
fprintf('No-crash trials after removing crash-coincident events: %d\n', length(nocrash_timestamps));

% Epoch NO-CRASH condition
nocrash = [];
for iTrial = 1:length(nocrash_timestamps)
    trial_epoch = nocrash_timestamps(iTrial)+epoch_lims(1):nocrash_timestamps(iTrial)+epoch_lims(2); % timestamps for this epoch
    trial_idx = interp1(nn_t, 1:length(nn_t), trial_epoch, 'nearest', 'extrap'); % sample index for this epoch
    nocrash(:,iTrial) = hr(trial_idx); % HR values for this epoch
end

% Create time index 
time = linspace(epoch_lims(1), epoch_lims(end), size(crash,1));

% Remove outlier trials (conservative)
badTrials = isoutlier(rms(crash,1), 'mean');
warning("Removing %g bad trial from CRASH condition", sum(badTrials))
crash(:,badTrials) = [];
badTrials = isoutlier(rms(nocrash,1), 'mean');
warning("Removing %g bad trial from NO-CRASH condition", sum(badTrials))
nocrash(:,badTrials) = [];
fprintf("Total trials for CRASH condition: %g \n", size(crash,2));
fprintf("Total trials for NO-CRASH condition: %g \n", size(nocrash,2));
sInfo(end).n_crash_trials = size(crash,2);
sInfo(end).n_nocrash_trials = size(nocrash,2);

% % Inter-event intervals
% crash_iei    = diff(sort(crash_timestamps));
% nocrash_iei  = diff(sort(nocrash_timestamps));
% fprintf('Crash    - n=%d, median IEI: %.2f s, min: %.2f s, max: %.2f s\n', ...
%     length(crash_timestamps), median(crash_iei), min(crash_iei), max(crash_iei));
% fprintf('No-crash - n=%d, median IEI: %.2f s, min: %.2f s, max: %.2f s\n', ...
%     length(nocrash_timestamps), median(nocrash_iei), min(nocrash_iei), max(nocrash_iei));
% % Histogram of inter-event intervals
% figure('color','w');
% subplot(2,1,1); histogram(crash_iei,   30); title('Crash IEI'); xlabel('s');
% subplot(2,1,2); histogram(nocrash_iei, 30); title('No-crash IEI'); xlabel('s');
% 
% % check if events overlap
% too_close_crash    = crash_iei    < abs(diff(epoch_lims));
% too_close_nocrash  = nocrash_iei  < abs(diff(epoch_lims));
% fprintf('Crash events too close together:    %d/%d\n', sum(too_close_crash),   length(crash_iei));
% fprintf('No-crash events too close together: %d/%d\n', sum(too_close_nocrash), length(nocrash_iei));
% 
% 
% % Are there duplicate/near-duplicate no-crash timestamps?
% fprintf('No-crash events within 0.1s of each other: %d\n', sum(nocrash_iei < 0.1));
% 
% % What does the no-crash event structure look like around a crash?
% % Print timestamps of first 20 no-crash events alongside crash events
% fprintf('\nFirst 20 no-crash timestamps:\n');
% disp(sort(nocrash_timestamps(1:20))')
% fprintf('\nFirst 10 crash timestamps:\n');
% disp(sort(crash_timestamps(1:10))')

% Compare conditions - ERP 
% plotHDI(time, nocrash_hr, crash_hr, 'mean', [], 'no crash','crash');    % 95% Bayesian HDIs
plotDiff(time, nocrash, crash, 'mean', 'SE', [], 'no crash','crash');   % 'SE' or 'CI'
title(sprintf('Subject %g - Heart Rate',sub_num));
ylabel('HR (in bpm)')
set(gcf,'Toolbar','none','Menu','none','NumberTitle', 'Off'); 
% xlim(epoch_lims); xlabel('Time (seconds)')
print(gcf, fullfile(PPG.filepath, 'HR-ERP.png'), '-dpng', '-r300');

save(fullfile(PPG.filepath, "ERP_PPG.mat"), "time", "nocrash", "crash", "hr", "nn_t")
save(fullfile(datapath, 'sInfo_ppg.mat'), 'sInfo')
