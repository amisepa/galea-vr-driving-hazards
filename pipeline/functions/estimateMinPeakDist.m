%% Estime mean peak distance from all availabel PPG channels
% 
% Copyright (C), Evolve Inc., Cedric Cannard, Nov 2024

function minPeakDist = estimateMinPeakDist(calib, minPeakHeight, fs)

num_chan = size(calib,2);
minPeakDist = nan(1,num_chan); % preallocate memory
for iChan = 1:num_chan
    [~, tmp_peaks] = findpeaks(calib(:,iChan), 'MinPeakHeight', minPeakHeight(iChan));
    tmp_rr = diff(tmp_peaks./fs);  % RR in samples
    % minPeakDist(:,iChan) = 10*trimmean(tmp_rr,20);  % 20% trimmed mean to account for outliers
    minPeakDist(iChan) = round(median(tmp_rr) * fs/2,2);  % best to use mean distance multiplied by half sample rate
end
