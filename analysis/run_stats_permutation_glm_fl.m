%% Copyright (c) 2026 Cedric Cannard. GPL-3.0 (see the repository LICENSE).

function [betas_obs, tvals_obs, tvals_H0, dz_map, pvals_obs, pvals_H0] = ...
    run_stats_permutation_glm_fl(Y_all, X, condition_col, nSub, nPerm, varargin)
%RUN_STATS_PERMUTATION_GLM_FL  Hierarchical GLM with Freedman-Lane permutation.
%
% Drop-in replacement for run_stats_permutation_glm_hierarchical WHEN THE
% DESIGN CONTAINS NUISANCE COVARIATES beyond the intercept and condition.
%
% WHY IT EXISTS. The library routine permutes the condition column and leaves
% every other column bound to its original trials:
%
%     Xp = X; Xp(:, 2) = cond_perm;
%
% With a two-column design that is exactly right - shuffling condition
% shuffles everything that carries trial identity. With a third column, such
% as the Alday per-trial baseline, it is not: under the null the covariate
% still explains genuine trial-specific variance in Y while condition has been
% scrambled, so the permuted models are not exchangeable with the observed one
% and the statistic inflates. Measured on this dataset, 19 of 20 label
% shuffles produced a "significant" cluster where about 1 was expected.
%
% WHAT THIS DOES INSTEAD. Freedman & Lane (1983). For each participant:
%
%   1. Fit the REDUCED model (everything except condition) to that
%      participant's trials, giving fitted values Yr and residuals Er.
%   2. Permute Er within the participant.
%   3. Rebuild the data as Y* = Yr + Er_permuted.
%   4. Refit the FULL model, design matrix untouched, and take the condition
%      coefficient.
%
% The design is never permuted, so the covariate stays attached to its own
% trial throughout. Only the part of the data the reduced model cannot explain
% is exchanged, which is the null hypothesis actually being tested.
%
% Level 2 is unchanged: subject-level condition coefficients are carried up
% and tested with a one-sample t across participants.
%
% INPUTS / OUTPUTS are identical to run_stats_permutation_glm_hierarchical, so
% callers only need to change the function name.
%
%   Freedman, D., & Lane, D. (1983). A nonstochastic interpretation of
%   reported significance levels. Journal of Business & Economic Statistics,
%   1(4), 292-298.
%   Winkler, A. M., et al. (2014). Permutation inference for the general
%   linear model. NeuroImage, 92, 381-397.
%
% Cedric Cannard, September 2026

p = inputParser;
p.addParameter('Subjects', [], @isnumeric);
p.addParameter('Method', 'WLS', @ischar);
p.addParameter('WeightType', 'Huber', @ischar);
p.addParameter('CondCol', 2, @isnumeric);
p.addParameter('Progress', true, @islogical);
p.parse(varargin{:});
subj_idx   = p.Results.Subjects;
method     = p.Results.Method;
weightType = p.Results.WeightType;
condCol    = p.Results.CondCol;
show_prog  = p.Results.Progress;

[nChan, nTime, nTrials] = size(Y_all);
Y = reshape(permute(Y_all, [3 1 2]), nTrials, nChan*nTime);   % [nTrials x nVox]

if isempty(subj_idx), error('Subjects index is required.'); end
sub_rows = arrayfun(@(s) find(subj_idx == s), 1:nSub, 'UniformOutput', false);

keepCols = setdiff(1:size(X,2), condCol);      % reduced model = all but condition
if numel(keepCols) == size(X,2)
    error('CondCol %d is not a column of X.', condCol);
end
if numel(keepCols) < 2
    warning(['Design has no nuisance covariate; plain label permutation is ' ...
        'already valid and cheaper. Freedman-Lane is harmless but redundant.']);
end

    function B = fitsub(Xs, Ys, w)
        switch upper(method)
            case 'OLS'
                B = pinv(Xs' * Xs) * (Xs' * Ys);
            otherwise                                   % WLS
                W = diag(w);
                B = pinv(Xs' * W * Xs) * (Xs' * W * Ys);
        end
    end

% ---------------- OBSERVED ----------------
if show_prog, fprintf('\n=== HIERARCHICAL GLM (Freedman-Lane) ===\n'); end
beta_obs = zeros(nSub, nChan*nTime);
Wsub  = cell(nSub,1);
Yr    = cell(nSub,1);      % reduced-model fit
Er    = cell(nSub,1);      % reduced-model residuals
for s = 1:nSub
    rows = sub_rows{s};
    Ys = Y(rows, :);  Xs = X(rows, :);
    if strcmpi(method, 'OLS')
        w = ones(numel(rows),1);
    else
        w = compute_wls_weights(Xs, Ys, weightType);
    end
    Wsub{s} = w;
    B = fitsub(Xs, Ys, w);
    beta_obs(s, :) = B(condCol, :);

    Xr = X(rows, keepCols);
    Br = fitsub(Xr, Ys, w);
    Yr{s} = Xr * Br;
    Er{s} = Ys - Yr{s};
end

b3 = permute(reshape(beta_obs', nChan, nTime, nSub), [3 1 2]);
% reshape, not squeeze: with nChan == 1 squeeze returns an nTime x 1 COLUMN,
% which later broadcasts against tvals_H0 into an nTime x nTime map.
betas_obs = reshape(mean(b3, 1), nChan, nTime);
sd_obs    = reshape(std(b3, 0, 1), nChan, nTime);
dz_map    = betas_obs ./ sd_obs;
tvals_obs = betas_obs ./ (sd_obs / sqrt(nSub));

% ---------------- PERMUTATIONS ----------------
if show_prog, fprintf('Freedman-Lane: %d permutations\n', nPerm); end
tvals_H0 = zeros(nChan, nTime, nPerm);
for iPerm = 1:nPerm
    beta_perm = zeros(nSub, nChan*nTime);
    for s = 1:nSub
        rows = sub_rows{s};
        Xs   = X(rows, :);
        pidx = randperm(numel(rows));
        Ystar = Yr{s} + Er{s}(pidx, :);          % design untouched, residuals exchanged
        B = fitsub(Xs, Ystar, Wsub{s});
        beta_perm(s, :) = B(condCol, :);
    end
    bp = permute(reshape(beta_perm', nChan, nTime, nSub), [3 1 2]);
    m  = reshape(mean(bp, 1), nChan, nTime);
    sd = reshape(std(bp, 0, 1), nChan, nTime);
    tvals_H0(:, :, iPerm) = m ./ (sd / sqrt(nSub));
    if show_prog && mod(iPerm, max(1, round(nPerm/10))) == 0
        fprintf('  %d%%\n', round(100*iPerm/nPerm));
    end
end

% ---------------- p-values (two-tailed, observed included in the null) ------
pvals_obs = (1 + sum(abs(tvals_H0) >= abs(tvals_obs), 3)) / (1 + nPerm);
pvals_H0  = zeros(nChan, nTime, nPerm);
for iPerm = 1:nPerm
    pvals_H0(:, :, iPerm) = ...
        (1 + sum(abs(tvals_H0) >= abs(tvals_H0(:, :, iPerm)), 3)) / (1 + nPerm);
end
if show_prog, fprintf('Done.\n'); end
end
