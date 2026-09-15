%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function EEG = fix_polarity(EEG, suspect_labels, lp_cutoff, threshold)
% FIX_POLARITY  Detect and correct reversed-polarity channels in EEGLAB data.
%
% Polarity reversals can occur when disc electrodes (e.g. Fp1, Fp2) are
% recorded with inverted amplifier leads relative to the rest of the montage.
% This function detects such reversals by comparing the sign of suspect
% channels against a robust reference signal at large-amplitude timepoints,
% where eye blinks dominate and the polarity inversion is unambiguous. The
% data are first lowpass filtered to suppress high-frequency noise (which is
% typically larger in frontal disc electrodes than in scalp electrodes seated
% in hair), and a median reference is computed across all non-suspect channels
% after excluding flat channels. Sign agreement is then assessed exclusively
% at the top 10% amplitude timepoints of the reference signal, where blink
% events provide a strong, broadband, common-mode deflection. If the fraction
% of timepoints where the suspect channel agrees in sign falls below
% (1 - threshold), its polarity is reversed in the original unfiltered data.
%
% Usage:
%   EEG = fix_polarity(EEG, suspect_labels)
%   EEG = fix_polarity(EEG, suspect_labels, lp_cutoff)
%   EEG = fix_polarity(EEG, suspect_labels, lp_cutoff, threshold)
%
% Inputs:
%   EEG             - EEGLAB EEG structure
%   suspect_labels  - cell array of channel labels to check, e.g. {'Fp1','Fp2'}
%   lp_cutoff       - lowpass cutoff frequency in Hz applied before sign
%                     comparison to suppress HF noise (default: 8)
%   threshold       - minimum fraction of sign agreement required to consider
%                     polarity correct; channels below (1 - threshold) are
%                     flipped. 0.6 means flip if fewer than 40% of peak
%                     timepoints agree in sign (default: 0.6)
%
% Output:
%   EEG             - EEG structure with polarity corrected in EEG.data;
%                     the correction is applied to the original unfiltered
%                     data, the filtered copy is discarded after detection

if nargin < 3 || isempty(lp_cutoff);  lp_cutoff = 8;  end
if nargin < 4 || isempty(threshold);  threshold = 0.6; end

chan_labels  = {EEG.chanlocs.labels};
suspect_idx  = find(ismember(chan_labels, suspect_labels));

if isempty(suspect_idx)
    warning('fix_polarity: none of the requested channels found.');
    return
end

% --- LP-filtered copy ---
EEG_lp   = pop_eegfiltnew(EEG, [], lp_cutoff);
ref_pool  = setdiff(1:EEG_lp.nbchan, suspect_idx);

% --- Exclude flat channels ---
ref_rms   = rms(EEG_lp.data(ref_pool, :), 2);
flat_mask = isoutlier(ref_rms, 'median') & (ref_rms < median(ref_rms));
good_ref  = ref_pool(~flat_mask);
if any(flat_mask)
    fprintf('fix_polarity: excluding flat channel(s): [%s]\n', ...
            strjoin(chan_labels(ref_pool(flat_mask)), ', '));
end

% --- Reference: median across good channels ---
ref_signal = median(EEG_lp.data(good_ref, :), 1);   % [1 x time]

% --- Focus on large-amplitude timepoints (blinks dominate here) ---
amp_thresh  = prctile(abs(ref_signal), 90);           % top 10% amplitude
blink_idx   = abs(ref_signal) > amp_thresh;
fprintf('fix_polarity: using %d / %d timepoints (top 10%% amplitude)\n', ...
        sum(blink_idx), numel(blink_idx));

% --- Check sign agreement at those timepoints ---
polarity_flipped = false(1, EEG.nbchan);

for ch = suspect_idx
    ch_signal   = EEG_lp.data(ch, :);
    sign_agree  = sign(ch_signal(blink_idx)) == sign(ref_signal(blink_idx));
    frac_agree  = mean(sign_agree);   % fraction of timepoints with same sign

    fprintf('  %s: sign agreement at peaks = %.3f', chan_labels{ch}, frac_agree);
    if frac_agree < (1 - threshold)
        polarity_flipped(ch) = true;
        fprintf('  --> REVERSED');
    end
    fprintf('\n');
end

clear EEG_lp

% --- Apply to original data ---
if any(polarity_flipped)
    EEG.data(polarity_flipped, :, :) = -EEG.data(polarity_flipped, :, :);
    fprintf('fix_polarity: reversed [%s]\n', strjoin(chan_labels(polarity_flipped), ', '));
else
    fprintf('fix_polarity: no reversal detected, data unchanged.\n');
end