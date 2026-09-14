function [mask_clusters, summary_tbl] = pull_clusters_tf(mask, tvals, time, foi, ...
    merge_clust, es, nSub)
% PULL_CLUSTERS_TF  Split a corrected time-frequency mask into per-cluster masks
% and a summary table.
%
% Lifted out of run_final_EEG_tf.m so that analysis/replot_tf_clusters.m can
% rebuild the cluster masks from a saved TF_stats_*.mat without recomputing the
% permutation GLM. run_final_EEG_tf.m calls it exactly as before.
%
% Cedric Cannard, August 2026

CC = bwconncomp(mask);
if CC.NumObjects == 0
    mask_clusters = {};
    summary_tbl   = table();
    return
end

dt        = mean(diff(time));
merge_smp = round(merge_clust / dt);
merged    = merge_nearby_clusters(CC, size(mask), merge_smp);
nClust    = length(merged);

mask_clusters = cell(nClust, 1);
rows          = cell(nClust, 1);

for ic = 1:nClust
    cmask = false(size(mask));
    cmask(merged{ic}) = true;
    mask_clusters{ic} = cmask;

    [fi, ti]      = find(cmask);
    t_range       = [time(min(ti))  time(max(ti))];
    f_range       = [foi(min(fi))   foi(max(fi))];
    [~, peak_idx] = max(abs(tvals(merged{ic})));
    peak_lin      = merged{ic}(peak_idx);
    [peak_fi, peak_ti] = ind2sub(size(mask), peak_lin);
    t_peak = tvals(peak_lin);

    if strcmp(es, 'd')
        es_val = t_peak / sqrt(nSub); es_lbl = 'Cohens_d';
    else
        es_val = t_peak / sqrt(t_peak^2 + nSub - 1); es_lbl = 'r';
    end

    rows{ic} = {ic, f_range(1), f_range(2), t_range(1), t_range(2), ...
        foi(peak_fi), time(peak_ti), t_peak, es_val, numel(merged{ic})};
end

summary_tbl = cell2table(vertcat(rows{:}), ...
    'VariableNames', {'Cluster','FreqMin_Hz','FreqMax_Hz','TimeMin_ms','TimeMax_ms', ...
    'PeakFreq_Hz','PeakTime_ms','Peak_t', es_lbl, 'Size_pts'});
disp(summary_tbl)
end


% ── MERGE NEARBY CLUSTERS ─────────────────────────────────────────────────
function merged = merge_nearby_clusters(CC, sz, merge_smp)
nC    = CC.NumObjects;
masks = false([sz, nC]);
for ic = 1:nC
    m = false(sz);
    m(CC.PixelIdxList{ic}) = true;
    % Fallback without Image Processing Toolbox:
    % masks(:,:,ic) = conv2(double(m), ones(1,merge_smp),'same') > 0;
    masks(:,:,ic) = imdilate(m, strel('rectangle', [1, merge_smp]));
end
labels = 1:nC;
for i = 1:nC
    for j = i+1:nC
        if any(masks(:,:,i) & masks(:,:,j), 'all')
            labels(labels == labels(j)) = labels(i);
        end
    end
end

unique_labels = unique(labels);
merged = cell(length(unique_labels), 1);
for k = 1:length(unique_labels)
    members = find(labels == unique_labels(k));
    idx = [];
    for m = members
        idx = [idx; CC.PixelIdxList{m}]; %#ok<AGROW>
    end
    merged{k} = unique(idx);
end
end
