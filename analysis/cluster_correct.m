%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function [mask, pcorr, info] = cluster_correct(tvals, tvals_H0, opts)
% CLUSTER_CORRECT  Cluster-mass permutation correction, one implementation for
% every analysis in this project.
%
% Replaces compute_mcc/correct_cluster, compute_mcc_fast and the local
% compute_mcc_tf, which had drifted apart; the three points below are what
% each of them did differently and why this exists.
%
% Three things this fixes relative to correct_cluster.m:
%
%   1. Cluster mass is the sum of |t|, not of signed t. correct_cluster summed
%      signed t and compared it against the 95th percentile of the MAXIMUM null
%      mass, so a predominantly negative cluster could never pass. The largest
%      effect in this dataset is negative.
%   2. Positive and negative t are clustered SEPARATELY. Clustering a two-tailed
%      p-map lets a positive and a negative region that touch in time merge into
%      one cluster and their masses add.
%   3. The observed and null maps are thresholded by the identical rule, a fixed
%      cluster-forming threshold from the t distribution. compute_mcc_tf
%      thresholded the observed map on p AND |t| but the null map on |t| alone.
%
% This is the same procedure as mne.stats.spatio_temporal_cluster_1samp_test,
% The MNE-Python cross-check that once lived alongside this file has been removed:
% the project is MATLAB-only and a second implementation that nobody maintains is
% a liability, not a check.
%
% INPUTS
%   tvals    : [nSpace x nTime] observed t-map. nSpace is channels (scalp) or
%              frequencies (time-frequency).
%   tvals_H0 : [nSpace x nTime x nPerm] null t-maps from the permutation GLM.
%   opts     : struct
%       .alpha      significance level, and the cluster-forming threshold
%                   (two-tailed) unless .tcrit is given. Default 0.05.
%       .df         degrees of freedom for the cluster-forming threshold.
%                   Required unless .tcrit is given.
%       .tcrit      cluster-forming threshold on |t|, overrides .alpha/.df.
%       .neighbours [nSpace x nSpace] logical channel adjacency. For scalp data.
%                   Leave empty for time-frequency data, where adjacency is
%                   4-connectivity in the frequency x time plane.
%       .minchan    require this many suprathreshold NEIGHBOURING channels at the
%                   same time point, applied iteratively (FieldTrip minnbchan).
%                   0 = standard adjacency clustering. Default 0.
%
% OUTPUTS
%   mask   : [nSpace x nTime] integer labels, 1..k for surviving clusters, 0
%            elsewhere. Labels are ordered by increasing corrected p.
%   pcorr  : [nSpace x nTime] corrected p per surviving cluster, NaN elsewhere.
%   info   : struct with .tcrit, .nullmax, .max_th, .clusters (table), .minchan
%
% Cedric Cannard, August 2026

if nargin < 3, opts = struct; end
if ~isfield(opts, 'alpha'),      opts.alpha = 0.05;  end
if ~isfield(opts, 'minchan'),    opts.minchan = 0;   end
if ~isfield(opts, 'neighbours'), opts.neighbours = []; end

[nSpace, nTime, ~] = size(tvals_H0);
nPerm = size(tvals_H0, 3);
assert(isequal(size(tvals), [nSpace nTime]), ...
    'tvals is %s but tvals_H0 is %s', mat2str(size(tvals)), mat2str(size(tvals_H0)));

if isfield(opts, 'tcrit') && ~isempty(opts.tcrit)
    tcrit = opts.tcrit;
else
    assert(isfield(opts, 'df') && ~isempty(opts.df), ...
        'opts.df is required unless opts.tcrit is given');
    tcrit = tinv(1 - opts.alpha/2, opts.df);
end

nb = opts.neighbours;
if ~isempty(nb)
    nb = logical(nb);
    nb = nb | nb.';
    nb(1:nSpace+1:end) = false;     % no self-adjacency
end

% ---------- null distribution of the maximum cluster mass ----------
nullmax = zeros(nPerm, 1);
parfor p = 1:nPerm
    nullmax(p) = max_cluster_mass(tvals_H0(:,:,p), tcrit, nb, opts.minchan);
end
max_th = prctile(nullmax, 100*(1 - opts.alpha));

% ---------- observed clusters ----------
[labels, masses, peakidx] = all_clusters(tvals, tcrit, nb, opts.minchan);

mask  = zeros(nSpace, nTime);
pcorr = nan(nSpace, nTime);
rows  = cell(0,7);

if ~isempty(masses)
    % Corrected p with the observed statistic included in the null, so p is
    % never exactly 0 (Phipson & Smyth 2010).
    pvals = (1 + sum(nullmax >= masses(:).', 1)) ./ (1 + nPerm);
    keep  = find(pvals <= opts.alpha);
    [~, ord] = sort(pvals(keep));
    keep = keep(ord);
    for k = 1:numel(keep)
        c = keep(k);
        sel = labels == c;
        mask(sel)  = k;
        pcorr(sel) = pvals(c);
        [ps, ts] = ind2sub([nSpace nTime], peakidx(c));
        rows(end+1,:) = {k, masses(c), pvals(c), sum(sel(:)), ps, ts, tvals(peakidx(c))}; %#ok<AGROW>
    end
end

info = struct('tcrit', tcrit, 'max_th', max_th, 'nullmax', nullmax, ...
    'minchan', opts.minchan, 'nObserved', numel(masses));
if isempty(rows)
    info.clusters = table();
else
    info.clusters = cell2table(rows, 'VariableNames', ...
        {'Cluster','Mass','pcorr','nPoints','PeakSpaceIdx','PeakTimeIdx','PeakT'});
end
end


% =====================================================================
function m = max_cluster_mass(t, tcrit, nb, minchan)
[~, masses] = all_clusters(t, tcrit, nb, minchan);
if isempty(masses), m = 0; else, m = max(masses); end
end


function [labels, masses, peakidx] = all_clusters(t, tcrit, nb, minchan)
% Cluster positive and negative excursions separately and pool the masses, so a
% positive and a negative region that touch cannot merge.
[labP, massP, pkP] = cluster_one_polarity(t  > tcrit, abs(t), nb, minchan);
[labN, massN, pkN] = cluster_one_polarity(t < -tcrit, abs(t), nb, minchan);

nP = numel(massP);
labels = labP;
labels(labN > 0) = labN(labN > 0) + nP;
masses  = [massP(:); massN(:)];
peakidx = [pkP(:);   pkN(:)];
end


function [labels, masses, peakidx] = cluster_one_polarity(sig, absT, nb, minchan)
[nSpace, nTime] = size(sig);
labels = zeros(nSpace, nTime);
masses = [];
peakidx = [];
if ~any(sig(:)), return, end

% FieldTrip minnbchan: drop points without enough suprathreshold neighbouring
% channels at the same time point, iterating until nothing more is removed.
if minchan > 0 && ~isempty(nb)
    changed = true;
    while changed
        nsig = double(nb) * double(sig);      % [nSpace x nTime] neighbour counts
        drop = sig & (nsig < minchan);
        changed = any(drop(:));
        sig(drop) = false;
    end
    if ~any(sig(:)), return, end
end

% Breadth-first labelling. Neighbours of (s,t) are (s,t±1) and, for scalp data,
% (s',t) for every channel s' adjacent to s. With nb empty this is plain
% 4-connectivity in the plane, which is what time-frequency maps need.
if isempty(nb)
    nbList = cell(nSpace,1);
    for s = 1:nSpace
        nbList{s} = intersect([s-1 s+1], 1:nSpace);
    end
else
    nbList = arrayfun(@(s) find(nb(s,:)), 1:nSpace, 'uni', false);
end

labels = zeros(nSpace, nTime);
k = 0;
stack = zeros(nSpace*nTime, 1);
for seed = find(sig(:)).'
    if labels(seed) > 0, continue, end
    k = k + 1;
    top = 1; stack(top) = seed; labels(seed) = k;
    while top > 0
        node = stack(top); top = top - 1;
        [s, tt] = ind2sub([nSpace nTime], node);
        for tn = [tt-1 tt+1]
            if tn >= 1 && tn <= nTime
                j = sub2ind([nSpace nTime], s, tn);
                if sig(j) && labels(j) == 0
                    labels(j) = k; top = top + 1; stack(top) = j;
                end
            end
        end
        for sn = nbList{s}
            j = sub2ind([nSpace nTime], sn, tt);
            if sig(j) && labels(j) == 0
                labels(j) = k; top = top + 1; stack(top) = j;
            end
        end
    end
end

masses  = accumarray(labels(labels>0), absT(labels>0), [k 1]);
peakidx = zeros(k,1);
for c = 1:k
    idx = find(labels == c);
    [~, w] = max(absT(idx));
    peakidx(c) = idx(w);
end
end
