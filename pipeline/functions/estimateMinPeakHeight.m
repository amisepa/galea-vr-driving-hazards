%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function minPeakHeight = estimateMinPeakHeight(ppgSignal, method)
% Estimate minimum peak height automatically
% Inputs:
%   ppgSignal - The PPG signal vector
%   method - Method to estimate minPeakHeight ('mad', 'std', 'percentile')
% Output:
%   minPeakHeight - Estimated minimum peak height

switch method
    case 'mad'
        % Method 1: Median Absolute Deviation (MAD) robust measure of variability
        % minPeakHeight = median(ppgSignal,'omitnan') + 0.5*mad(ppgSignal);
        minPeakHeight = trimmean(ppgSignal,20) + 0.5*mad(ppgSignal);
        % minPeakHeight = mean(ppgSignal,'omitnan') + 0.5*mad(ppgSignal);
        % minPeakHeight = trimmean(ppgSignal,20);

    case 'std'
        % Method 2: Standard Deviation
        minPeakHeight = median(ppgSignal) + 0.5*std(ppgSignal);
        % minPeakHeight = trimmean(ppgSignal,20) + 0.5*std(ppgSignal,'omitnan');

    case 'percentile'
        % Method 3: Percentile (e.g., 90th percentile)
        minPeakHeight = prctile(ppgSignal, 90);

    case 'trimmean'
        % Method 4: trimmean mean (positive values only)
        minPeakHeight = trimmean(ppgSignal(ppgSignal>0),20);

    otherwise
        error('Unknown method. Choose "mad", "std", or "percentile".');
end

minPeakHeight = round(minPeakHeight,2);

