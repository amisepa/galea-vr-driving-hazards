%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function [data_cleaned, removed_channels] = flag_bad_eeg_channels(data, fs, min_corr, ignored_quantile, window_len, max_broken_time)
% Clean EEG channels by identifying and removing consistently low-correlation channels.
% Inputs:
%   data            - [channels × samples] EEG matrix
%   fs              - Sampling rate in Hz
%   min_corr        - Minimum correlation threshold (e.g. 0.5)
%   ignored_quantile- Fraction of most-correlated channels to ignore (e.g. 0.1)
%   window_len      - Window length in seconds (e.g. 2)
%   max_broken_time - Max allowed bad time (in seconds or fraction of total duration)

if nargin < 3 || isempty(min_corr), min_corr = 0.5; end
if nargin < 4 || isempty(ignored_quantile), ignored_quantile = 0.1; end
if nargin < 5 || isempty(window_len), window_len = 2; end
if nargin < 6 || isempty(max_broken_time), max_broken_time = 0.25; end

[C, S] = size(data);
data = double(data);
window_len = round(window_len * fs);
offsets = 1:window_len:(S - window_len);
W = length(offsets);
retained = 1:(C - ceil(C * ignored_quantile));

% Flag low-correlation windows
flagged = false(C, W);
for w = 1:W
    idx = offsets(w):(offsets(w) + window_len - 1);
    window_data = data(:, idx)';
    R = abs(corrcoef(window_data));
    for ch = 1:C
        sorted_corrs = sort(R(ch, [1:ch-1, ch+1:end]));
        top_corrs = sorted_corrs(1:length(retained));
        flagged(ch, w) = all(top_corrs < min_corr);
    end
end

% Determine which channels are bad
bad_counts = sum(flagged, 2);
if max_broken_time < 1
    max_flagged = round(S * max_broken_time / window_len);
else
    max_flagged = round(max_broken_time / window_len);
end

removed_channels = bad_counts > max_flagged;
data_cleaned = data(~removed_channels, :);

