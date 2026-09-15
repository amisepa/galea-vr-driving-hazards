%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function [nn_intervals, nn_t, idx_corrected] = clean_rr_intervals(rr_t, rr_intervals)
    % clean_rr_intervals - Detects and corrects abnormal heartbeats in RR interval time series.
    %
    % INPUT:
    % rr_t         - Vector of timestamps (seconds) corresponding to each RR interval.
    % rr_intervals - Vector of RR intervals in seconds.
    % peaks        - Vector of sample indices of detected peaks.
    %
    % OUTPUT:
    % nn_intervals - Vector of corrected NN intervals in seconds.
    % new_peaks    - Updated sample indices of peaks after corrections.
    % idx_corrected - Logical array indicating which intervals were corrected (true if corrected).
    
    % Parameters
    lower_limit = 0.375;  % Minimum valid RR interval (0.375 s = 160 bpm)
    upper_limit = 1.333;      % Maximum valid RR interval (1.333 s = 45 bpm)
    
    nn_intervals = rr_intervals;
    nn_t = rr_t';
    % new_peaks = peaks;
    idx_corrected = false(length(rr_intervals), 1);

    % Step 1: Remove overly short RR intervals
    short_rr = diff(rr_t) <= lower_limit;
    if any(short_rr)
        warning('Removing %g overly short RR intervals', sum(short_rr));
    end
    nn_intervals(short_rr) = [];
    nn_t(short_rr) = [];
    % new_peaks(short_rr) = [];
    idx_corrected(short_rr) = true;

    % figure('Color', 'w'); hold on;
    % plot(nn_t, nn_intervals, 'Color',[0.6350 0.0780 0.1840], 'LineWidth', 2, 'DisplayName', 'Short RR');

    % Step 2: Recalculate gaps based on updated nn_intervals
    gaps = nn_intervals > upper_limit;
    if any(gaps)
        warning('Interpolating %g gaps in the RR intervals', sum(gaps));
    end
    idx_corrected(gaps) = true;
    nn_intervals = interp1(nn_t(~gaps), nn_intervals(~gaps), nn_t, 'spline', 'extrap');
    % plot(nn_t, nn_intervals, 'Color',[0.3010 0.7450 0.9330], 'LineWidth', 2, 'DisplayName', 'Gaps');

    % Step 3: Interpolate outliers
    outliers = isoutlier(nn_intervals, 'median');
    if any(outliers)
        warning('Interpolating %g outlier RR intervals', sum(outliers));
    end
    idx_corrected(outliers) = true;
    % plot(nn_t, nn_intervals, 'Color', [0.9290 0.6940 0.1250], 'LineWidth', 2, 'DisplayName', 'Outliers');
    % nn_intervals = interp1(nn_t(~outliers), nn_intervals(~outliers), nn_t, 'pchip');
    nn_intervals = interp1(nn_t(~outliers), nn_intervals(~outliers), nn_t, 'spline', 'extrap');

    % Step 4L interpolate sharp spikes
    spikes = FindSpikesInRR(nn_intervals, .2);
    if any(spikes)
        warning('Interpolating %g outlier RR intervals', sum(outliers));
    end
    idx_corrected(spikes) = true;
    % plot(nn_t, nn_intervals, 'Color', [0.9290 0.6940 0.1250], 'LineWidth', 2, 'DisplayName', 'Outliers');
    % nn_intervals = interp1(nn_t(~spikes), nn_intervals(~spikes), nn_t, 'pchip');
    nn_intervals = interp1(nn_t(~spikes), nn_intervals(~spikes), nn_t, 'spline', 'extrap');

    % plot(nn_t, nn_intervals, 'k', 'LineWidth', 2, 'DisplayName', 'Final');
    % legend('show');

    % Output results
    % fprintf('Total corrections: %g\n', sum(idx_corrected));
end

%% clean RR intervals that change more than a given threshold
% (eg., th = 0.2 = 20%) with respect to the median value of the previous 5
% and next 5 RR intervals (using a forward-backward approach).
%
% INPUTS:
%       RR : a single row of rr interval data in seconds
%       th : threshold percent limit of change from one interval to the next
% OUTPUTS:
%       idxRRtoBeRemoved : a single vector of indexes related to RR
%                          intervals corresponding to a change > th

function idxRRtoBeRemoved = FindSpikesInRR(RR, th)

if size(RR,1)>size(RR,2)
    RR = RR';
end

% Forward search
FiveRR_MedianVal = medfilt1(RR,5); % compute as median RR(-i-2: i+2)

% shift of three position to align with to corresponding RR
FiveRR_MedianVal = [RR(1:5) FiveRR_MedianVal(3:end-3)];
rr_above_th = (abs(RR-FiveRR_MedianVal)./FiveRR_MedianVal)>=th;

RR_forward = RR;
RR_forward(rr_above_th) = NaN;

% Backward search
RRfilpped = fliplr(RR);
FiveRR_MedianVal = medfilt1(RRfilpped,5); % compute as median RR(-i-2: i+2)
% shift of three position to aligne with to corresponding RR
FiveRR_MedianVal = [RRfilpped(1:5) FiveRR_MedianVal(3:end-3)];
rr_above_th = find(abs(RRfilpped-FiveRR_MedianVal)./FiveRR_MedianVal>=th);
rr_above_th = sort(length(RR)-rr_above_th+1);

RR_backward = RRfilpped;
RR_backward(rr_above_th) = NaN;

% Combine
idxRRtoBeRemoved = (isnan(RR_forward) & isnan(RR_backward));

end