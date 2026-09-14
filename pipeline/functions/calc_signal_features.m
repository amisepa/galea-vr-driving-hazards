function [metrics, seg_idx]= calc_signal_features(signal, sig_type, fs, winSize, overlap)
% Calculate signal features for quality assessment
% Separately process baseline, highpass, and lowpass filtered signals
% Cedric Cannard, 2024

metrics = [];

% Default sliding window size (1 s)
if isempty(winSize)
    winSize = 1;
end
winSize = winSize * fs;  % convert to samples

% Overlap
if overlap
    stepSize = floor(winSize / 2); % 50% overlap
else
    stepSize = winSize;  % no overlap (for ML training!)
end

if size(signal,2) > size(signal,1)
    signal = signal';
end

% Filter depending on signal
if strcmpi(sig_type, 'ppg')
    [hp_b, hp_a] = butter(2, 0.75/(fs/2), 'high');           % highpass: preserves signal and noise for pSNR
    [bp_b, bp_a] = butter(2, [0.75 3]/(fs/2), 'bandpass');   % bandpass: for clean pulse extraction
elseif strcmpi(sig_type, 'eeg')
    [hp_b, hp_a] = butter(3, 3/(fs/2), 'high');             % highpass = noisy signal (3 hz to reduce weight of ocular artifacts)
    [bp_b, bp_a] = butter(3, [3 30]/(fs/2), 'bandpass');    % bandpass = clean signal (3 hz to reduce weight of ocular artifacts)
end

% High-pass filter
hp_filtered = filtfilt(hp_b, hp_a, signal);   % zero-phase filtering

% Notch filter at 60 Hz
if strcmpi(sig_type, 'eeg')
    wo = 60 / (fs/2);      % Normalized frequency
    bw = wo / 40;          % Bandwidth (Q=40 gives narrow notch)
    [bn, an] = iirnotch(wo, bw);
    hp_filtered = filtfilt(bn, an, hp_filtered);
end

% Band-pass filter
bp_filtered = filtfilt(bp_b, bp_a, signal);   % zero-phase filtering

% Iterate through sliding windows
num_samples = size(signal, 1);
% indices = 1:winSize:num_samples;
indices = 1:stepSize:(num_samples - winSize + 1);
for iSeg = 1:length(indices)
    % Break if exceeding signal bounds
    tSeg = indices(iSeg):(indices(iSeg) + winSize - 1);
    if tSeg(end) > num_samples, break; end
    seg_idx(iSeg) = tSeg(1);

    % Extract windowed signals
    % raw_sig = signal(tSeg); % Original signal
    hp_sig = hp_filtered(tSeg); % Highpass (≥0.5 Hz), for pSNR
    bp_sig = bp_filtered(tSeg); % Bandpass (0.8–3 Hz), for tSNR and morphology
    % baseline_sig = baseline_filtered(tSeg); % Baseline filtered signal

    % Flat line percentage
    metrics.flat(iSeg) = sum(abs(diff(hp_sig)) < 1e-6) / length(hp_sig) * 100;

    % --- Precompute windowed FFT once for frequency-domain metrics ---
    N = length(hp_sig);
    f = (0:N-1)*(fs/N); % full spectrum
    half_idx = 1:floor(N/2);
    f = f(half_idx);

    % Apply window and compute one-sided FFT
    win = hamming(N)';  % hamming taper
    hp_sig_win = hp_sig(:)'.*win;
    fft_win = fft(hp_sig_win);
    Y = abs(fft_win).^2;
    psd = Y(half_idx) / (fs * sum(win.^2));  % Apply window power correction
    psd_norm = psd / (sum(psd) + eps);      % Normalize to unit area

    % pSNR (frequency-domain from literature)
    if strcmpi(sig_type, 'ppg')
        signal_band = (f >= 0.8 & f <= 2.5) | ...
            (f >= 1.6 & f <= 5.0) | ...
            (f >= 2.4 & f <= 7.5);
    elseif strcmpi(sig_type, 'eeg')
        signal_band = (f > 4 & f <= 25);  % includes theta, alpha, beta
        signal_power = sum(psd(signal_band));
        noise_power  = sum(psd(~signal_band));
        metrics.pSNR(iSeg) = 10 * log10(signal_power / (noise_power + eps));
    end
    signal_power = sum(psd(signal_band));
    noise_power  = sum(psd(~signal_band));
    metrics.pSNR(iSeg) = 10 * log10(signal_power / (noise_power + eps));

    % tSNR (time-domain from literature)
    % ac_amp = max(bp_sig) - min(bp_sig);       % AC component
    ac_amp = prctile(bp_sig, 95) - prctile(bp_sig, 5);  % robust AC
    residual = bp_sig - smooth(bp_sig, 0.2 * fs);   % remove slow trend
    rms_noise = sqrt(mean(residual.^2));            % high-freq noise
    metrics.tSNR(iSeg) = 20 * log10(ac_amp / (rms_noise + eps));

    % SNR1 - simple Persaval approach
    signal_power = var(bp_sig);
    noise_power = var(hp_sig - bp_sig);
    metrics.SNR1(iSeg) = 10*log10(signal_power / (noise_power+eps));

    % SNR2 - classic SNR in dB
    clean_power = sum(psd(signal_band));
    noise_power = sum(psd(~signal_band));
    metrics.SNR2(iSeg) = 10*log10(clean_power / (noise_power + eps));

    % Residual MAD
    % metrics.residual_mad(iSeg) = mad(hp_sig - bp_sig, 0);
    metrics.residual_mad(iSeg) = 10*log10(mad(hp_sig - bp_sig, 0) ./ mad(bp_sig,0)+eps);
    % metrics.residual_mad(iSeg) = 10*log10(mad(hp_sig - bp_sig, 0).^2 / (mad(bp_sig, 0).^2 + eps));

    
    % Time-domain statistical features
    metrics.rms(iSeg) = rms(bp_sig);        % RMS
    metrics.kurt(iSeg) = kurtosis(bp_sig);  % Kurtosis
    metrics.skew(iSeg) = skewness(bp_sig);  % Skewness

    % Nonlinear/Entropy features
    probabilities = histcounts(bp_sig, 10, 'Normalization', 'probability');
    probabilities(probabilities == 0) = [];
    metrics.shannon_entropy(iSeg) = -sum(probabilities .* log2(probabilities)); % Shannon entropy
    metrics.spec_entropy(iSeg) = -sum(psd_norm .* log2(psd_norm));

    % PPG Morphological Features
    if strcmpi(sig_type, 'ppg')
        [pks, locs] = findpeaks(bp_sig);                % Peaks
        metrics.PPI_var(iSeg) = std(diff(locs)/fs);     % Pulse-to-pulse variability
        metrics.amp_var(iSeg) = var(pks);               % Amplitude variability

        % Peak and Trough Analysis for Symmetry
        [troughs, trough_locs] = findpeaks(-bp_sig); % Find troughs (negative peaks)
        if ~isempty(pks) && ~isempty(trough_locs)
            metrics.symmetry(iSeg) = abs(mean(pks) - abs(mean(bp_sig(trough_locs)))); % Peak symmetry
        else
            metrics.symmetry(iSeg) = NaN; % Handle case with no peaks/troughs
        end
        if ~isempty(troughs)
            metrics.trough_mean(iSeg) = mean(-troughs); % Mean amplitude of troughs
            metrics.trough_var(iSeg) = var(-troughs);  % Variance of trough amplitudes
        else
            metrics.trough_mean(iSeg) = NaN; % No troughs detected
            metrics.trough_var(iSeg) = NaN; % No troughs detected
        end
    end

    % Slope Features
    slopes = diff(bp_sig);                      % Signal slopes
    metrics.mean_slope(iSeg) = mean(slopes);    % Mean slope
    metrics.slope_var(iSeg) = var(slopes);      % Slope variability

    % Zero-Crossing Features and Fractal Dimension
    diff_signal = diff(bp_sig); % First-order differences
    zc_indices = find(diff_signal(1:end-1) .* diff_signal(2:end) < 0);  % Zero-crossing indices
    zero_crossings = length(zc_indices);                                % Count zero-crossings
    metrics.zc(iSeg) = zero_crossings;                                  % Zero-crossing rate
    metrics.zc_int(iSeg) = mean(diff(zc_indices) / fs);                 % Zero-crossing intervals
    n = length(bp_sig);                                                 % Length of the filtered signal
    metrics.fractal(iSeg) = log10(n) / (log10(n) + log10(n / (n + 0.4 * zero_crossings))); % Petrosian fractal dimension

    % Autocorrelation Features
    max_lag = fs; % Max lag = 1 second
    autocorr_vals = xcorr(bp_sig, max_lag, 'coeff');
    autocorr_vals = autocorr_vals(max_lag+1:end);
    metrics.lag1_autocorr(iSeg) = autocorr_vals(2); % Lag-1 autocorrelation

    % Energy-related Features
    metrics.signal_energy(iSeg) = sum(bp_sig.^2); % Signal energy
    metrics.signal_power(iSeg) = mean(bp_sig.^2); % Signal power
end
