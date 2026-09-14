function plot_tf_grandavg(time, foi, CRASH_AVG, NOCRASH_AVG, tvals, mask, mask_clusters, summary_tbl, mcc_type, mode, out_path)
% PLOT_TF_GRANDAVG  Grand-average time-frequency panels: each condition, their
% difference, and the t-map with surviving clusters outlined.
%
% Extracted from the run_final_* time-frequency scripts alongside pull_clusters_tf and
% plot_tf_clusters, so a saved statistics file can be re-plotted from
% TF_stats_*.mat without recomputing the permutation GLM. run_final_EEG_tf.m
% calls it exactly as before.
%
% Cedric Cannard, August 2026


% Headless guard. MATLAB -batch aborts or hangs on figure creation; skip
% plotting when there is no desktop.
if ~usejava('desktop')
    disp('  (headless: skipping plot_tf_grandavg)');
    return
end

diff_map  = CRASH_AVG - NOCRASH_AVG;
% clim_raw  = max(abs([CRASH_AVG(:); NOCRASH_AVG(:)]));
clim_diff = max(abs(diff_map(:)));
clim_t    = max(abs(tvals(:)));

switch mode
    case 'baseline_db',  pwr_lbl = 'dB re baseline'; diff_lbl = '\Delta dB';
    case 'aperiodic_db', pwr_lbl = 'dB (aperiodic)'; diff_lbl = '\Delta dB';
    otherwise,           pwr_lbl = 'Power';           diff_lbl = '\Delta Power';
end

% fig = figure('Color','w','Position',[100 100 1400 340]);
fig = figure('Color','w','Position',[100 100 1800 340]);


% Panel 1: Crash
subplot(1,4,1)
imagesc(time, foi, CRASH_AVG); axis xy
colormap(gca, parula)
cb = colorbar; cb.Label.String = pwr_lbl;
xlabel('Time (ms)'); ylabel('Frequency (Hz)')
% title(sprintf('Grand avg: Crash (%s)', strrep(mode,'_',' ')))
title('Grand avg: Crash')
ylim([foi(1) foi(end)])

% Panel 2: No-crash
subplot(1,4,2)
imagesc(time, foi, NOCRASH_AVG); axis xy
colormap(gca, parula)
cb = colorbar; cb.Label.String = pwr_lbl;
xlabel('Time (ms)')
% title(sprintf('Grand avg: No-crash (%s)', strrep(mode,'_',' ')))
title('Grand avg: No-crash')
ylim([foi(1) foi(end)])

% Panel 3: Difference
subplot(1,4,3)
img_h3 = imagesc(time, foi, diff_map); axis xy
set(img_h3, 'AlphaData', ~isnan(diff_map))
set(gca, 'Color', [0.85 0.85 0.85])
clim([-clim_diff clim_diff]); colormap(gca, diverging_cmap)
cb = colorbar; cb.Label.String = diff_lbl;
xlabel('Time (ms)'); 
title('Crash - No-crash')
ylim([foi(1) foi(end)])


% Panel 4: t-map, grey out non-significant or show empty grey if no clusters
subplot(1,4,4)
if any(mask, 'all')
    % Mask: show only significant pixels, grey out rest
    tvals_masked = tvals;
    tvals_masked(~mask) = nan;
    img_h = imagesc(time, foi, tvals_masked); axis xy
    set(img_h, 'AlphaData', ~isnan(tvals_masked))
    set(gca, 'Color', [0.85 0.85 0.85])
    clim([-clim_t clim_t]); colormap(gca, diverging_cmap)
    cb = colorbar; cb.Label.String = 't';
    % Draw cluster outlines and number each at peak location
    hold on
    if ~isempty(mask_clusters)
        for iClust = 1:length(mask_clusters)
            cmask = mask_clusters{iClust};
            contour(time, foi, double(cmask), [0.5 0.5], 'k-', 'LineWidth', 1.5)

            % Place cluster number just to the right of the cluster
            tvals_in_clust = tvals .* cmask;
            [~, peak_lin] = max(abs(tvals_in_clust(:)));
            [peak_fi, ~] = ind2sub(size(tvals), peak_lin);
            right_ti = max(find(any(cmask, 1)));   % rightmost time index of cluster
            % Offset slightly beyond the right edge
            t_offset = (time(end) - time(1)) * 0.02;   % 2% of time axis width
            text(time(right_ti) + t_offset, foi(peak_fi), sprintf('%d', iClust), ...
                'Color', 'k', 'FontSize', 11, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
                'BackgroundColor', 'w', 'Margin', 2)
        end
    end
    hold off
else
    % No significant clusters: show grey panel
    set(gca, 'Color', [0.85 0.85 0.85]); axis xy
    xlim([time(1) time(end)]); ylim([foi(1) foi(end)])
    text(mean(time), mean(foi), 'No significant clusters', ...
        'HorizontalAlignment', 'center', 'FontSize', 11, 'Color', [0.4 0.4 0.4])
end
xlabel('Time (ms)');
% title(sprintf('t-map (corr=%d)', mcc_type))
title('t-map')
ylim([foi(1) foi(end)])

set(findall(fig, 'type', 'axes'), 'FontSize', 14, 'FontWeight', 'bold', 'TickDir', 'out', 'Box', 'off')
set(findall(fig, 'type', 'text'), 'FontSize', 14, 'FontWeight', 'bold')
set(findall(fig, 'type', 'colorbar'), 'FontSize', 14, 'FontWeight', 'bold')

saveas(fig, fullfile(out_path, sprintf('TF_grandavg_corr-%d.fig', mcc_type)));
print(fig,  fullfile(out_path, sprintf('TF_grandavg_corr-%d.png', mcc_type)), '-dpng','-r300');
end
