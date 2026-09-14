%% How extended is the pre-stimulus effect, really?
%
% WHY THIS EXISTS. The pre-stimulus result is reported as a cluster at
% "3-30 Hz, -641 to -464 ms, peak 5 Hz at -540 ms". Those boundaries are where
% the cluster-forming threshold happens to be crossed, which is not the same
% thing as where the effect is. If the underlying difference is a sustained
% offset across the whole analysed window, then quoting a 177 ms latency range
% invites the reader to interpret it as an anticipatory transient time-locked to
% the upcoming event, which would be the wrong reading and a consequential one:
% a transient a few hundred milliseconds before onset and a tonic state
% difference spanning seconds have completely different explanations.
%
% This script does not test anything. It DESCRIBES the observed t-map, so that
% Section 3.5 can state the shape of the effect rather than only its
% suprathreshold extent.
%
% Cedric Cannard, September 2026

clear; close all; clc
paths = galea_set_paths();   % configure paths (edit galea_set_paths.m for your machine)
RES = paths.res_tf_causal;
S = load(fullfile(RES,'none','pre-stim','TF_stats_pre.mat'), 'tvals','mask','time','foi');

t = S.tvals;
[nF, nT] = size(t);
nSub = 16;                       % the TF analysis is at N = 16
thr  = tinv(1 - 0.05/2, nSub-1); % the cluster-forming threshold used by the analysis

fprintf('Pre-stimulus t-map: %d frequencies x %d time points (%.0f to %.0f ms)\n', ...
    nF, nT, min(S.time), max(S.time));
fprintf('Cluster-forming threshold t(%d) = %.3f\n\n', nSub-1, thr);

fprintf('SIGN OF THE MAP\n');
fprintf('  positive          : %.1f%% of the plane\n', 100*mean(t(:) > 0));
fprintf('  mean t            : %+.3f   median %+.3f\n', mean(t(:)), median(t(:)));
fprintf('  range             : %+.3f to %+.3f\n\n', min(t(:)), max(t(:)));

sup = abs(t) > thr;
fprintf('SUPRATHRESHOLD POINTS\n');
fprintf('  above threshold   : %.1f%% of the plane (%d of %d points)\n', ...
    100*mean(sup(:)), sum(sup(:)), numel(t));
fprintf('  of those, positive: %d      negative: %d\n', ...
    sum(t(sup) > 0), sum(t(sup) < 0));
fprintf('  surviving cluster : %d points (%.1f%% of the plane)\n\n', ...
    sum(S.mask(:)), 100*mean(S.mask(:)));

fprintf('MEAN t BY 100 ms BIN  (is there any interval without the effect?)\n');
edges = floor(min(S.time)/100)*100 : 100 : 0;
for b = 1:numel(edges)-1
    sel = S.time >= edges(b) & S.time < edges(b+1);
    if ~any(sel), continue; end
    blk = t(:, sel);
    fprintf('  %6.0f to %6.0f ms : mean t %+.2f   %5.1f%% suprathreshold\n', ...
        edges(b), edges(b+1), mean(blk(:)), 100*mean(abs(blk(:)) > thr));
end

fprintf('\nMEAN t BY FREQUENCY BAND\n');
bands = {'3-7 Hz',[3 7]; 'theta-alpha 7-13',[7 13]; 'beta 13-30',[13 30]};
for b = 1:size(bands,1)
    sel = S.foi >= bands{b,2}(1) & S.foi <= bands{b,2}(2);
    blk = t(sel, :);
    fprintf('  %-18s : mean t %+.2f   %5.1f%% suprathreshold\n', ...
        bands{b,1}, mean(blk(:)), 100*mean(abs(blk(:)) > thr));
end

T = table(mean(t(:) > 0)*100, mean(t(:)), sum(sup(:))/numel(t)*100, ...
    sum(t(sup) > 0), sum(t(sup) < 0), sum(S.mask(:)), ...
    'VariableNames', {'pct_positive','mean_t','pct_suprathreshold', ...
    'n_supra_positive','n_supra_negative','n_cluster_points'});
writetable(T, fullfile(RES,'prestim_extent.csv'));
fprintf('\nwrote prestim_extent.csv\n');
