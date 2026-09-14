function [badChan, flaggedRatio] = flag_bad_eeg_channels_window(eeg_data, srate, min_corr, ignored_quantile, maxTol, overlap) 

% Flags bad EEG channels using sliding window analysis
% 
% Inputs:
%   eeg_data         - channels x samples EEG data
%   srate            - sampling rate in Hz
%   min_corr         - minimum correlation threshold (default: 0.55, paper value)
%   ignored_quantile - quantile of correlations to ignore (default: 0.2, paper value)
%   maxTol           - maximum tolerance for flagged ratio (default: 0.3, paper value)
%   overlap          - overlap fraction, e.g., 0.75 for 75% (default: 0.5)
%
% Outputs:
%   badChan          - logical vector of bad channels
%   flaggedRatio     - ratio of windows each channel was flagged

if nargin < 3 || isempty(min_corr),         min_corr         = 0.55; end  % paper value (Cannard & Yesilbas 2026)
if nargin < 4 || isempty(ignored_quantile), ignored_quantile = 0.2;  end  % paper value
if nargin < 5 || isempty(maxTol),           maxTol           = 0.3;  end  % paper value
if nargin < 6 || isempty(overlap),          overlap          = 0.5; end

% Window parameters
winSize  = 2 * srate;
stepSize = floor(winSize * (1 - overlap));
num_samples = size(eeg_data, 2);
C           = size(eeg_data, 1);

% Window indices
indices     = 1:stepSize:(num_samples - winSize + 1);
num_windows = length(indices);

% Initialize outputs
amprms    = zeros(C, num_windows);
flat_flag = false(C, num_windows);
corr_flag = false(C, num_windows);

fprintf('Analyzing %d windows...\n', num_windows);

for iWin = 1:num_windows
    win_t    = indices(iWin):(indices(iWin) + winSize - 1);
    data_win = double(eeg_data(:, win_t));

    % RMS amplitude per channel
    % amprms(:, iWin) = rms(data_win, 2);
    amprms(:, iWin) = mad(data_win, [], 2);

    % Flat line detection per channel
    flat_flag(:, iWin) = max(abs(diff(data_win, 1, 2)), [], 2) < 1e-7;

    % Correlation-based flagging
    R = abs(corrcoef(data_win'));
    R(logical(eye(C))) = NaN;
    retain_n     = C - ceil(C * ignored_quantile);
    sorted_corrs = sort(R, 2, 'ascend');
    top_corrs    = sorted_corrs(:, 1:retain_n);
    corr_flag(:, iWin) = all(top_corrs < min_corr, 2);

    if mod(iWin, 10) == 0
        fprintf('  Progress: %d/%d windows\n', iWin, num_windows);
    end
end

% RMS outliers across windows for each channel
rms_outlier = isoutlier(amprms, 1);   % C x num_windows

% Combine flags (uncomment corr_flag line to include correlation mode)
% combined_flag = rms_outlier | flat_flag;
combined_flag = rms_outlier & corr_flag | flat_flag;

% Fraction of flagged windows per channel
flaggedRatio = sum(combined_flag, 2) / num_windows;   % C x 1
badChan      = flaggedRatio > maxTol;

fprintf('Found %d bad channels (%.1f%%)\n', sum(badChan), 100*sum(badChan)/C);

end
