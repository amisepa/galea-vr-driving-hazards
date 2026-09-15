%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function [ppg_data, flat, snr, sqi_mu, sqi_badRatio, corrected_ratio, NN_t, NN] = clean_galea_ppg(ppg_data, time, fs, filt_type, detect_meth, vis)

sqi_mu = [];
sqi_badRatio = [];

[nSamples, nChan] = size(ppg_data);

% High-pass filter
[b, a] = butter(2, 0.5/(fs/2), 'high');
if strcmpi(filt_type, 'causal')
    ppg_data = filter(b, a, ppg_data);      % causal filtering (to compare with real-time processing)
else
    ppg_data = filtfilt(b, a, ppg_data);    % zero-phase noncausal filtering
end

% Calculate SNR to select best PPG channel
overlap = false; % 50% overlap
for iChan = 1:nChan
    [metrics, seg_idx] = calc_signal_features(ppg_data(:,iChan), 'ppg', fs, 2, overlap);
    flat(iChan) = (sum(metrics.flat) / length(metrics.flat)) * 100;
    snr(iChan) = round(median(metrics.pSNR),1);
end

% Lowpass filter
[b, a] = butter(3, 3/(fs/2), 'low');
ppg_data = filtfilt(b, a, ppg_data); % zero-phase noncausal filtering


% Brainbeats function to detect heartbeats and SQI
% addpath('D:\MATLAB\BrainBeats\functions')
params.fs = fs; params.heart_signal = 'ppg'; 
% params.ppg_detect_mode = 'valleys';
rr = {}; rr_t = {}; rPeaks = {};
sqi = {};  annot = {}; 
nn = {}; nn_t = {}; nPeaks = {};
corrected_ratio = zeros(1, nChan);
for iChan = 1:nChan
    [rr{iChan}, rr_t{iChan}, rPeaks{iChan}] = get_RR(ppg_data(:,iChan), time, params);

    % [sqi, sqi_mu, annot] = get_sqi_ppg(rPeaks{iChan}, ppg_data(:,iChan),fs);
    % sqi_badRatio(iChan) = round(sum(sqi{iChan} < .9 | isnan(sqi{iChan})) / length(sqi{iChan})*100,1);

    [nn{iChan}, nn_t{iChan}, nPeaks{iChan}, idx_bad{iChan}, idx_interp{iChan}] = clean_rr( ...
        rr_t{iChan}, rr{iChan}, ppg_data(rPeaks{iChan}, iChan), rPeaks{iChan}, ...
        'interpolate_missing', true, 'ecg_signal', ppg_data(:,iChan), 'sig_t', time, 'fs', fs);

    % [nn, nn_t, nPeaks, idx_bad, idx_interp] = clean_rr(rr_t, rr, ecg_sig(rPeaks), rPeaks, ...
    %     'interpolate_missing', true, 'ecg_signal', ecg_sig, 'sig_t', sig_t, 'fs', ECG.srate );

    % rr_t{iChan}(1)       = [];
    % nn_t{iChan}(1)       = [];
    % peaks{iChan}(1)      = [];
    % nPeaks{iChan}(1) = [];

    corrected_ratio(iChan) = sum(idx_bad{iChan}) / length(idx_bad{iChan}) * 100;
    fprintf('Channel %g: %g/%g (%.2f%%) of heart beats were abnormal and corrected.\n', ...
        iChan, sum(idx_bad{iChan}), length(idx_bad{iChan}), corrected_ratio(iChan));

    if vis
        plot_NN(time, ppg_data(:,iChan), rr_t{iChan}, rr{iChan}, rPeaks{iChan}, ...
            nn_t{iChan}, nn{iChan}, nPeaks{iChan}, 'ppg');
    end
end

% print SNR
fprintf("SNR for channel 1: %g dB\n", snr(1))
fprintf("SNR for channel 2: %g dB\n", snr(2))

% Select best channel for analysis
[~, bestChan] = max(snr);
NN_t = nn_t{bestChan};
NN = nn{bestChan};

