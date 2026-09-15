%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function [mask, pcorr, max_th] = compute_mcc_fast(tvals, pvals, tvals_H0, pvals_H0, alpha, chanlocs, nSub) %#ok<INUSD>
% COMPUTE_MCC_FAST  Deprecated shim. Calls cluster_correct.
%
% This used to be a faster reimplementation of compute_mcc(..., 2, ...), kept
% because correct_cluster hangs on noise-like maps. It is now a thin wrapper so
% that every analysis in the project goes through the one correction routine,
% analysis/cluster_correct.m. Prefer calling that directly in new code.
%
% Behaviour differs from the old compute_mcc_fast in three ways, all deliberate,
% all documented in manuscript/stats_review_2026-08.md:
%   - standard adjacency clustering (minchan = 0) rather than minnbchan = 2;
%   - positive and negative t clustered separately;
%   - a fixed cluster-forming t threshold applied identically to the observed
%     and null maps, rather than thresholding on the permutation p-map.
%
% pvals and pvals_H0 are ignored: cluster_correct thresholds on t. They remain
% in the signature so existing call sites keep working.
%
% nSub is optional. Without it the degrees of freedom are inferred from the
% number of permutations being a one-sample design, which is not knowable, so
% pass nSub when you can.
%
% Cedric Cannard, August 2026

if nargin < 7 || isempty(nSub)
    error(['compute_mcc_fast now requires nSub as the 7th argument so the ' ...
           'cluster-forming threshold can be set. Better: call cluster_correct ' ...
           'directly.']);
end

params.method = 'triangulation';
[~, nb] = get_channelneighbors(chanlocs, params);

opts = struct('alpha', alpha, 'df', nSub - 1, 'neighbours', nb, 'minchan', 0);
[mask, pcorr, info] = cluster_correct(tvals, tvals_H0, opts);
max_th = info.max_th;
end
